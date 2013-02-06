(*
Zipperposition: a functional superposition prover for prototyping
Copyright (C) 2012 Simon Cruanes

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.
*)

(** {1 Extracting lemmas from proofs} *)

open Types
open Symbols

module T = Terms
module C = Clauses
module S = FoSubst
module Lits = Literals
module Utils = FoUtils

(** {2 Utils to build lemmas} *)

(** A possible lemma, i.e. a cut of the graph *)
type candidate_lemma = {
  cl_conclusion : literal array;
  cl_premises : literal array list;
}

exception GotchaLittlePclause of Theories.named_formula * Patterns.mapping

(** Find a named formula [nf] associated with those literals. If none is
    available, create a new named formula.
    This returns both the named_formula and a mapping from [lits]
    to the nf.nf_pclause. *)
let get_nf kb lits =
  let open Theories in
  try
    Patterns.Map.retrieve kb.kb_patterns lits ()
      (fun () pc mapping nf ->
        raise (GotchaLittlePclause (nf, mapping)));
    (* failed to find a matching named_formula *)
    let name = next_name kb in
    (* create a new named_formula for this clause *)
    let pc = Patterns.pclause_of_lits lits in
    let nf = { Patterns.np_name = name; Patterns.np_pattern = pc; } in
    (* add the named formula to the KB *)
    add_named kb [nf];
    (* find a match *)
    match Patterns.match_pclause pc lits with
    | [] -> assert false
    | mapping::_ -> nf, mapping
  with GotchaLittlePclause (nf, mapping) ->
    nf, mapping  (* matched against already existing formula *)

(** Convert a candidate_lemma to a proper lemma. It may have the side-effect
    to add some named formulas to the KB. *)
let candidate_to_lemma kb cl =
  let module Th = Theories in
  let module Pat = Patterns in
  (* map: a list of (symbol, variable number) *)
  let map = ref [] in
  let var_idx = ref (-1) in
  (* get an atom for the named formula with the given mapping *)
  let atom_of_nf nf mapping =
    let name, args = nf.Pat.np_name, nf.Pat.np_pattern.Pat.pc_vars in
    (* create an atom, binding concrete symbols to variables *)
    let args = List.map
      (fun i -> if i < Patterns.symbol_offset
        then `Symbol (Patterns.special_symbols.(i)) (* special constant *)
        else
          (* lookup symbol for this pattern symbol, then variable for the symbol *)
          let symbol = Ptmap.find i mapping.Pat.m_symbol in
          try `Var (List.assq symbol !map)
          with Not_found ->
            (* associate a new variable with this symbol *)
            let n = !var_idx in
            decr var_idx;
            map := (symbol, n) :: !map;
            `Var n)
      args in
    name, args
  in
  (* atom for conclusion *)
  let conclusion_nf, conclusion_mapping = get_nf kb cl.cl_conclusion in
  let conclusion_atom = atom_of_nf conclusion_nf conclusion_mapping in
  (* atoms for premises *)
  let premises_atoms = List.map
    (fun premise ->
      let nf, mapping = get_nf kb premise in atom_of_nf nf mapping)
    cl.cl_premises in
  (* return the lemma *)
  { Th.lemma_conclusion = conclusion_atom;
    Th.lemma_premises = premises_atoms; }

(** 'simplicity' heuristic for a list of literals. The lower, the better. *)
let simplicity lits =
  let w = Lits.weight_lits lits
  and d = Lits.depth_lits lits
  and n = Array.length lits in
  if not (C.is_cnf lits) then max_float /. 10.
  else float_of_int (n * d + w)

(** {2 Cut extraction} *)

(** The idea here is, given a clause [c] in a proof graph, to find
    a cut [P] of the subgraph composed of ancestors of [c], such
    that any path from an axiom [a] to [c] contains at least one
    clause of [P].
    That means that from the conjunction of clauses in [P], [c] is provable. *)

(** Combine two float heuristics (both of them beeing low for
    interesting cases) *)
let combine_heuristics simplicity depth =
  (simplicity ** 1.2) /. (depth *. 5.)

(** Find a cut for the given proof, from its ancestors, or
    raise Not_found if no cut that covers a big enough portion
    of the proof can be found. *)
let cut graph proof =
  let module G = Proof.ProofGraph in
  (* graph of reversed inference edges: [c] -> [c'] if [c'] is a premise
     in the inference that proves [c] *)
  let graph = G.rev graph in
  assert (G.is_dag graph);
  (* leaves are axioms, they have no premises *)
  let leaves = Sequence.to_set
    (module G.S : Set.S with type elt = compact_clause proof 
                         and type t = G.S.t)
    (G.leaves graph) in 
  (* set of selected nodes (clauses) of the graph, to eventually form a cut *)
  let cut = ref G.S.empty in
  (* explore paths from [proof] to [leaves] and that contain no clause from [cut] *)
  let rec explore path v =
    if G.S.mem v !cut then ()
    else if G.S.mem v leaves then cut_path path (* cut path *)
    else Sequence.iter
      (fun (e, v') -> explore ((v',e,v)::path) v')
      (G.next graph v)
  (* explore repeatedly, until no open path is found *)
  and repeat () =
    try explore [] proof  (* no path is open, stop *)
    with Exit ->
      repeat ()  (* some path has been closed *)
  (* select an element of the path, and add it to [cut] *)
  and cut_path path =
    let length = List.length path in
    (* heuristic cost of the proof, at given distance from axioms? *)
    let heuristic p depth =
      if depth = length
        then infinity
        else combine_heuristics
          (simplicity (Proof.proof_lits p))
          (float_of_int depth)
    in
    match path with
    | [] -> assert false
    | (p,_,_)::path' ->
      (* by default, choose the first clause *)
      try
        let best = ref (p, heuristic p 1) in
        let _ = List.fold_left
          (fun depth (p,_,_) ->
            (* the path has been closed by cut, meanwhile *)
            (if G.S.mem p !cut then raise Exit);
            (* [p] is a proof in the path *)
            let h = heuristic p depth in
            let best_proof, best_h = !best in
            (if h < best_h then
              best := (p, h));
            depth+1)
          2 path'
        in
        cut := G.S.add (fst !best) !cut;
        raise Exit  (* notify that a path has been closed *)
      with Exit -> ()  (* already cut *)
  in
  repeat ();
  (* convert the cut to a list *)
  G.S.elements !cut

(** Pretty print the graph, including the cut, in given file *)
let pp_cut_dot ~name filename (graph, cut) = 
  (* DOT printer of this [cut] of the graph *)
  let cut_dot_printer =
    (* convert to set *)
    let module G = Proof.ProofGraph in
    let cut = Sequence.to_set
      (module G.S : Set.S with type elt = compact_clause proof 
                           and type t = G.S.t)
      cut in
    let print_vertex proof =
      let lits = Proof.proof_lits proof in
      let label = `Label (Utils.sprintf "@[<h>%a (%.2F)@]"
        Lits.pp_lits lits (simplicity lits)) in
      let attributes = [`Shape "box"; `Style "filled"] in
      let attributes =
        if Proof.proof_lits proof = [||] then `Color "red" :: `Label "[]" :: attributes
        else if G.S.mem proof cut then `Color "green" :: label :: attributes
        else if Proof.is_axiom proof then label :: `Color "yellow" :: attributes
        else label :: attributes in
      attributes
    and print_edge v1 e v2 =
      [`Label e]
    in
    Proof.ProofGraph.mk_dot_printer ~print_vertex ~print_edge
  in
  (* print graph on file *)
  let out = open_out filename in
  try
    (* write on the opened out channel *)
    let formatter = Format.formatter_of_out_channel out in
    Format.printf "%% print cut-graph to %s@." filename;
    Proof.ProofGraph.pp cut_dot_printer ~name formatter
      (Proof.ProofGraph.to_seq graph);
    Format.fprintf formatter "@.";
    close_out out
  with _ -> close_out out

(** {2 Lemma learning} *)

(** From the given proof of the empty clause, find a cut [P] of
    its premises, and learn p_1 & p_2 & ... & p_{n-1} => p_n *)
let learn_empty ~meta proof =
  let kb = meta.Theories.meta_kb in
  try
    (* find a good cut of the proof of $false *)
    let graph = Proof.to_graph proof in
    let proofs = cut graph proof in
    pp_cut_dot ~name:"cut" "learn_empty.dot" (graph, Sequence.of_list proofs);
    (* favor unit clauses, their negation is still a clause *)
    let heuristic p = 
      let h = simplicity (Proof.proof_lits p) in
      let h = if Array.length (Proof.proof_lits p) <= 1 then h else h *. 3. in
      h
    in
    match proofs with
    | [] -> failwith "empty proof cut?"
    | p::proofs' ->
      (* select the most suitable clause to serve as the conclusion of the lemma *)
      let _, best_i, best_p, _ = List.fold_left
        (fun (cur_i, best_i, best_p, best_h) p' ->
          let h = heuristic p' in
          if h < best_h
            then (cur_i+1, cur_i, p', h)
            else (cur_i+1, best_i, best_p, best_h))
        (1, 0,  p, heuristic p) proofs'
      in
      (* premises: all other clauses *)
      let premises = Utils.list_remove proofs best_i in
      let premises = List.map Proof.proof_lits premises in
      (* conclusion: negation of chosen clause *)
      let ord = meta.Theories.meta_ctx.ctx_ord in
      let conclusion = Lits.term_of_lits (Proof.proof_lits best_p) in
      let conclusion = [|Lits.mk_neq ~ord (T.close_forall conclusion) T.true_term|] in
      (* build lemma *)
      let candidate = { cl_premises=premises; cl_conclusion=conclusion; } in
      let lemma = candidate_to_lemma kb candidate in
      Some lemma
  with Not_found ->
    None  (* no good cut *)

(** From the given proof [c], find a cut [P] of its premises,
    and learn the lemma p_1 & p_2 & ... & p_n => c *)
let learn_subproof ~meta proof =
  let kb = meta.Theories.meta_kb in
  try
    (* find a good cut of [proof] *)
    let graph = Proof.to_graph proof in
    let proofs = cut graph proof in
    (* premises: clauses of the cut *)
    let premises = List.map Proof.proof_lits proofs in
    (* conclusion: negation of chosen clause *)
    let conclusion = Proof.proof_lits proof in
    let candidate = { cl_premises=premises; cl_conclusion=conclusion; } in
    let lemma = candidate_to_lemma kb candidate in
    Some lemma
  with Not_found ->
    None  (* no good cut *)

(** {2 Search for salient clauses *)

(** Find a list of {b salient} clauses in the given proof. Salient clauses
    are small clauses that have many descendants in the proof, and are
    close to the conclusion. Those clauses should be good candidates
    for [learn_subproof].
    Implementation should rely on PageRank on the reverse graph. *)
let salient_clauses proof = []  (* TODO *)

(** {2 Batteries-included lemma learning} *)

(** Maximum number of lemmas that can be learnt from one proof *)
let max_lemmas = ref 3

(** Given an empty clause (and its proof), look in the proof for lemmas. *)
let search_lemmas meta proof =
  assert (Proof.proof_lits proof = [||]);
  let open Theories in
  (* learn subproofs *)
  let salient = Utils.list_take !max_lemmas (salient_clauses proof) in
  let lemmas = List.map (learn_subproof ~meta) salient in
  (* learn from empty clause (full proof) *)
  let lemmas = learn_empty ~meta proof :: lemmas in
  (* flatten ('a option list -> 'a list) *)
  let lemmas = Utils.list_flatmap (function None -> [] | Some x -> [x]) lemmas in
  (* only keep lemmas that give safe rules *)
  let lemmas = List.filter
    (fun lemma ->
      let rule = rule_of_lemma lemma in
      Logic.check_safe rule)
    lemmas
  in
  lemmas

(** Update the KB of this meta-prover by learning from
    the given (empty) clause's proof. The KB is modified
    in place. *)
let learn_and_update meta hc =
  let open Theories in
  let kb = meta.meta_kb in
  (* learn from this proof *)
  let lemmas = search_lemmas meta hc.hcproof in
  let lemmas = List.map
    (fun lemma ->
      Format.printf "%%   learn @[<h>%a@]@." pp_lemma lemma;
      lemma)
    lemmas
  in
  (* store new lemmas *)
  add_lemmas kb lemmas
