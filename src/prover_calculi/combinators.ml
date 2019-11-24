open Logtk
open Libzipperposition

module T = Term
module Ty = Type
module Lits = Literals
module Lit = Literal


type conv_rule = T.t -> T.t option
exception IsNotCombinator

let k_enable_combinators = Flex_state.create_key ()

module type S = sig
  module Env : Env.S
  module C : module type of Env.C

  (** {6 Registration} *)
  val setup : unit -> unit
end

(* Helper function for defining combinators *)
(* see mk_s *)
let ty_s =
  let db_alpha = Ty.bvar 2 and db_beta = Ty.bvar 1 and db_gamma = Ty.bvar 0 in
  
  let open Type in
  let prefix ty = forall @@ forall @@ forall ty in
  prefix
    ([[db_alpha; db_beta] ==> db_gamma; [db_alpha] ==> db_beta; db_alpha]
      ==> db_gamma)

(* see mk_c *)
let ty_c =
  let db_alpha = Ty.bvar 2 and db_beta = Ty.bvar 1 and db_gamma = Ty.bvar 0 in
  
  let open Type in
  let prefix ty = forall @@ forall @@ forall ty in
  prefix
    ([[db_alpha; db_beta] ==> db_gamma; db_beta; db_alpha] 
      ==> db_gamma)

(* see mk_b *)
let ty_b =
  let db_alpha = Ty.bvar 2 and db_beta = Ty.bvar 1 and db_gamma = Ty.bvar 0 in
  
  let open Type in
  let prefix ty = forall @@ forall @@ forall ty in
  prefix
    ([[db_alpha] ==> db_beta; [db_gamma] ==> db_alpha; db_gamma] 
    ==> db_beta)

(* see mk_k *)
let ty_k =
  let db_alpha = Ty.bvar 1 and db_beta = Ty.bvar 0 in  

  let open Type in
  forall @@ forall ([db_beta; db_alpha] ==> db_beta)

(* see mk_i *)
let ty_i =
  let db_alpha = Ty.bvar 0 in  

  let open Type in
  forall ([db_alpha] ==> db_alpha)


let [@inline] mk_comb comb_head ty ty_args args =
  (* optmization: if args is empty, the whole 
    ty_args will be traversed *)
  if CCList.is_empty args then (
    T.app_builtin ~ty comb_head ty_args
  ) else T.app (T.app_builtin ~ty comb_head ty_args) args

(* make S combinator with the type:
  Παβγ. (α→β→γ) → (α→β) → α → γ *)
let mk_s ?(args=[]) ~alpha ~beta ~gamma =
  let ty = Ty.apply ty_s [Type.of_term_unsafe (alpha : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (beta : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (gamma : Term.t :> InnerTerm.t);] in
  mk_comb Builtin.SComb ty [alpha;beta;gamma] args

(* make C combinator with the type:
  Παβγ. (α→β→γ) → β → α → γ *)
let mk_c ?(args=[]) ~alpha ~beta ~gamma =
  let ty = Ty.apply ty_c [Type.of_term_unsafe (alpha : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (beta : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (gamma : Term.t :> InnerTerm.t);] in
  mk_comb Builtin.CComb ty [alpha;beta;gamma] args

(* make B combinator with the type:
  Παβγ. (α→β) → (γ→α) → γ → β *)
let mk_b ?(args=[]) ~alpha ~beta ~gamma =
  let ty = Ty.apply ty_b [Type.of_term_unsafe (alpha : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (beta : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (gamma : Term.t :> InnerTerm.t);]  in
  mk_comb Builtin.BComb ty [alpha;beta;gamma] args

(* make K combinator with the type:
  Παβ. β → α → β *)
let mk_k ?(args=[]) ~alpha ~beta =
  let ty = Ty.apply ty_k [Type.of_term_unsafe (alpha : Term.t :> InnerTerm.t);
                          Type.of_term_unsafe (beta : Term.t :> InnerTerm.t)] in
  mk_comb Builtin.KComb ty [alpha;beta] args

(* make I combinator with the type:
  Πα. α → α *)
let mk_i ?(args=[]) ~alpha =
  let ty = Ty.apply ty_i [Type.of_term_unsafe (alpha : Term.t :> InnerTerm.t)] in
  mk_comb Builtin.IComb ty [alpha] args

(* {2 Helper functions} *)
let [@inline] term_has_comb ~comb t =
  match T.view t with
  | T.AppBuiltin(hd, _) when Builtin.equal comb hd -> true
  | _ -> false

(* Returns the cobminator head, type arguments and real arguments 
  of a combinator *)
let [@inline] unpack_comb t =
  match T.view t with 
  | T.AppBuiltin(hd, args) when T.hd_is_comb hd ->
    let ty_args, real_args = List.partition Term.is_type args in
    (hd, ty_args, real_args)
  | _ -> raise IsNotCombinator

module Make(E : Env.S) : S with module Env = E = struct
  module Env = E
  module C = Env.C
  module Ctx = Env.Ctx
  module Fool = Fool.Make(Env)

  (* Given type arguments of S, calculate correct type arguments 
    for B *)
  let s2b_tyargs ~alpha ~beta ~gamma =
    (beta, gamma, alpha)

  (* {3 Narrowing and optimization functions} *)

  (* Rules for optimizing the abf algorithm, as laid out in the paper 
    Martin W. Bunder -- Some Improvements to Turner's Algorithm for 
    Bracket Abstraction \url{https://ro.uow.edu.au/eispapers/1962/}

    They are numbered as they are numbered in the paper.
    Some of the rules are applicable only for SKBCI combinators,
    but due to the abf algorithm design it is easy to extend it.
  *)

  (* [1]. S (K X) (K Y) -> K (X Y) *)
  let opt1 t =
    try 
      let c_kind,ty_args,args = unpack_comb t in
      if Builtin.equal Builtin.SComb c_kind then (
        match args,ty_args with 
        | [u;v],[alpha;_;beta] ->
          begin match unpack_comb u, unpack_comb v with
          | (Builtin.KComb,_,[x]), (Builtin.KComb,_,[y]) ->
            let xy = Term.app x [y] in
            Some (mk_k ~args:[xy] ~alpha ~beta )
          | _ -> None end
        | _ -> None
      ) else None
    with IsNotCombinator -> None

  (* [2]. S (K X) I -> X *)
  let opt2 t =
    try
      let c_kind,_,args = unpack_comb t in
      if Builtin.equal Builtin.SComb c_kind then (
        match args with 
        | [u;v] ->
          begin match unpack_comb u, unpack_comb v with 
          | (Builtin.KComb, _, [x]), (Builtin.IComb, _, []) ->
            Some x
          | _ -> None end
        | _ -> None
      ) else None
    with IsNotCombinator -> None

  (* [3]. S (K X) Y -> B X Y *)
  let opt3 t =
    try 
      let c_kind,ty_args,args = unpack_comb t in
      if Builtin.equal Builtin.SComb c_kind then (
        match args,ty_args with 
        | [u;y], [alpha;beta;gamma] ->
          begin match unpack_comb u with 
          | (Builtin.KComb, _, [x])->
            let alpha,beta,gamma = s2b_tyargs ~alpha ~beta ~gamma in
            Some (mk_b ~args:[x;y] ~alpha ~beta ~gamma)
          | _ -> None end
        | _ -> None
      ) else None
    with IsNotCombinator -> None

  (* [4]. S X (K Y) -> C X Y *)
  let opt4 t =
    try
      let c_kind,ty_args,args = unpack_comb t in
      if Builtin.equal Builtin.SComb c_kind then (
        match args,ty_args with 
        | [x;u], [alpha;beta;gamma] ->
          begin match unpack_comb u with 
          | (Builtin.KComb, _, [y])->
            Some (mk_c ~args:[x;y] ~alpha ~beta ~gamma)
          | _ -> None end
        | _ -> None
      ) else None
    with IsNotCombinator -> None

  (* Definition of S:
      S X Y Z t1 ... tn -> X Z (Y Z) t1 ... tn *)
  let narrowS t =
    try
      let c_kind,_,args = unpack_comb t in
      if Builtin.equal Builtin.SComb c_kind then (
        match args with 
        | x :: y :: z :: rest ->
          Some (T.app x (z :: (T.app y [z]) ::rest))
        | _ -> None
      ) else None
    with IsNotCombinator -> None
  
  (* Definition of B:
      B X Y Z t1 ... tn -> X (Y Z) t1 ... tn *)
  let narrowB t =
    try
      let c_kind,_,args = unpack_comb t in
      if Builtin.equal Builtin.BComb c_kind then (
        match args with 
        | x :: y :: z :: rest ->
          Some (T.app x ((T.app y [z]) ::rest))
        | _ -> None
      ) else None
    with IsNotCombinator -> None
  
  (* Definition of C:
      C X Y Z t1 ... tn -> X Z Y t1 ... tn *)
  let narrowC t =
    try
      let c_kind,_,args = unpack_comb t in
      if Builtin.equal Builtin.CComb c_kind then (
        match args with 
        | x :: y :: z :: rest ->
          Some (T.app x (z :: y ::rest))
        | _ -> None
      ) else None
    with IsNotCombinator -> None
  
  (* Definition of K:
      K X Y t1 ... tn -> X t1 ... tn *)
  let narrowK t =
    try
      let c_kind,_,args = unpack_comb t in
      if Builtin.equal Builtin.KComb c_kind then (
        match args with 
        | x :: y :: rest ->
          Some (T.app x rest)
        | _ -> None
      ) else None
    with IsNotCombinator -> None
  
  (* Definition of I:
      I X t1 ... tn -> X t1 ... tn *)
  let narrowI t =
    try
      let c_kind,_,args = unpack_comb t in
      if Builtin.equal Builtin.IComb c_kind then (
        match args with 
        | x :: rest ->
          Some (T.app x rest)
        | _ -> None
      ) else None
    with IsNotCombinator -> None

  let curry_optimizations = [opt1;opt2;opt3;opt4]
  let narrow_rules = [narrowS; narrowB; narrowC; narrowK; narrowI]

  let apply_rw_rules ~rules t =
    let rec aux = function 
    | f :: fs ->
      begin match f t with 
      | Some t' -> 
        assert (Type.equal (T.ty t) (T.ty t'));
        t'
      | None -> aux fs end
    | [] -> t in
    aux rules

  let narrow t =
    let steps = ref 0 in
    let rec do_narrow t =
      match T.view t with 
      | T.Const _ | T.Var _ | T.DB _-> t
      | T.AppBuiltin(hd, args) -> 
        let args' = List.map do_narrow args in
        let t =
          if T.same_l args args' then t
          else T.app_builtin ~ty:(T.ty t) hd args' in
        narrow_head t
      | T.App(hd, args) ->
        let hd' = do_narrow hd and args' = List.map do_narrow args in
        let t = 
          if T.equal hd hd' && T.same_l args args' then t
          else T.app hd' args' in
        narrow_head t
      | T.Fun _ ->
        let tys, body = T.open_fun t in
        let body' = do_narrow body in
        if T.equal body body' then t
        else T.fun_l tys body'
    and narrow_head t =
      let t' = apply_rw_rules ~rules:narrow_rules t in
      if T.equal t t' then t
      else (incr steps; do_narrow t') in
    do_narrow t, !steps

  (* Assumes beta-reduced, eta-short term *)
  let abf ~rules t =
    let rec abstract ~bvar_ty t =
      match T.view t with 
      | T.DB 0 -> mk_i ~alpha:bvar_ty ~args:[]
      | T.DB i -> 
        let ty = T.ty t in
        mk_k ~alpha:bvar_ty ~beta:(Term.of_ty ty) ~args:[T.bvar ~ty (i-1)]
      | T.Const _ | T.Var _ ->
        let beta = Term.of_ty @@ T.ty t in
        mk_k ~alpha:bvar_ty ~beta ~args:[t]
      | T.AppBuiltin _ | T.App _ -> 
        let hd_mono, args = T.as_app_mono t in
        assert(not @@ T.is_fun hd_mono);
        let hd_conv =
          if T.is_app hd_mono || T.is_appbuiltin hd_mono then (
            let beta = Term.of_ty @@ T.ty hd_mono in
            mk_k ~alpha:bvar_ty ~beta ~args:[hd_mono]
          ) else abstract ~bvar_ty hd_mono in
        let _, raw_res = List.fold_left (fun (l_ty, l_conv) r ->
          let r_conv = abstract ~bvar_ty r in
          let ret_ty = Ty.apply_unsafe l_ty [(r :> InnerTerm.t)] in
          let raw_res =
            mk_s ~alpha:bvar_ty ~beta:(Term.of_ty @@ T.ty r) 
                ~gamma:(Term.of_ty ret_ty) ~args:[l_conv;r_conv] in
          ret_ty, apply_rw_rules ~rules raw_res
        ) (T.ty hd_mono, hd_conv) args in
        apply_rw_rules ~rules raw_res
      | T.Fun _ -> 
        invalid_arg "all lambdas should be abstracted away!" in

    let rec aux t =
      match T.view t with 
      | T.AppBuiltin _ | T.App _ ->
        let hd_mono, args = T.as_app_mono t in
        let args' = List.map aux args in
        
        assert (not (T.is_fun hd_mono));
        if T.same_l args args' then t
        else T.app hd_mono args' (* flattens AppBuiltin if necessary *)
      | T.Fun(ty, body) ->
        let body' = aux body in
        abstract ~bvar_ty:(Term.of_ty ty) body'
      | _ ->  t in
    aux t


  exception E_i of Statement.clause_t
  let pp_in pp_f pp_t pp_ty = function
    | Output_format.O_zf -> Statement.ZF.pp pp_f pp_t pp_ty
    | Output_format.O_tptp -> Statement.TPTP.pp pp_f pp_t pp_ty
    | Output_format.O_normal -> Statement.pp pp_f pp_t pp_ty
    | Output_format.O_none -> CCFormat.silent
  let pp_clause_in o =
    let pp_term = T.pp_in o in
    let pp_type = Type.pp_in o in
    pp_in (Util.pp_list ~sep:" ∨ " (SLiteral.pp_in o pp_term)) pp_term pp_type o

  let result_tc =
    Proof.Result.make_tc
      ~of_exn:(function E_i c -> Some c | _ -> None)
      ~to_exn:(fun i -> E_i i)
      ~compare:compare
      ~pp_in:pp_clause_in
      ~is_stmt:true
      ~name:Statement.name
      ~to_form:(fun ~ctx st ->
        let conv_c c =
          CCList.to_seq c 
          |> Iter.flat_map (fun l -> SLiteral.to_seq l)
          |> Iter.map (fun t -> Term.Conv.to_simple_term ctx t)
          |> Iter.to_list
          |> TypedSTerm.Form.or_ in
        Statement.Seq.forms st
        |> Iter.map conv_c
        |> Iter.to_list
        |> TypedSTerm.Form.and_)
      ()


    let encode_lit ~rules l =
      SLiteral.map (abf ~rules) l
    
    let rec encode_clause ~rules = function 
      | [] -> []
      | l :: ls -> 
        encode_lit ~rules l :: encode_clause ~rules ls

    let enocde_stmt st =
      let rules = curry_optimizations in
      let rule = Proof.Rule.mk "lambdas_to_combs" in
      let as_proof = 
        Proof.S.mk (Statement.proof_step st) (Proof.Result.make result_tc st) in
      let proof = 
        Proof.Step.esa ~rule [Proof.Parent.from as_proof] in

      match Statement.view st with
      | Statement.Def _ | Statement.Rewrite _ | Statement.Data _ 
      | Statement.Lemma _ | Statement.TyDecl _ -> E.cr_skip
      | Statement.Goal lits | Statement.Assert lits ->
        let lits' = encode_clause ~rules lits in
        E.cr_return @@ [E.C.of_forms ~trail:Trail.empty lits' proof]
      | Statement.NegatedGoal (skolems,clauses) -> 
        let clauses' = 
          List.map (fun c -> 
            E.C.of_forms ~trail:Trail.empty (encode_clause ~rules c) proof) 
          clauses in
        E.cr_add clauses'
        (* E.cr_return @@ 
          Statement.neg_goal ~proof ~skolems (List.map (encode_clause ~opts) clauses) *)
    
    let comb_narrow c =
      let new_lits = Literals.map (fun t -> fst @@ narrow t) (C.lits c) in
      if Literals.equal (C.lits c) new_lits then (
        SimplM.return_same c
      ) else (
        let proof = Proof.Step.simp [C.proof_parent c] 
                      ~rule:(Proof.Rule.mk "narrow combinators") in
        let new_ = C.create ~trail:(C.trail c) ~penalty:(C.penalty c) 
                    (Array.to_list new_lits) proof in
        SimplM.return_new new_
      )

    let tyvarA = HVar.fresh ~ty:Ty.tType ()
    let tyvarB = HVar.fresh ~ty:Ty.tType ()
    let tyvarC = HVar.fresh ~ty:Ty.tType ()

    let type_of_vars ?(args=[]) ~ret =
      let open Ty in
      if CCList.is_empty args then Ty.var ret
      else List.map Ty.var args ==> Ty.var ret

    (* Create the arguments of type appropriate to be applied to the combinator *)
    let s_arg1 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[tyvarA;tyvarB] ~ret:tyvarC) ()
    let s_arg2 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[tyvarA] ~ret:tyvarB) ()

    let b_arg1 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[tyvarA] ~ret:tyvarB) ()
    let b_arg2 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[tyvarC] ~ret:tyvarA) ()

    let c_arg1 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[tyvarA;tyvarB] ~ret:tyvarC) ()
    let c_arg2 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[] ~ret:tyvarB) ()

    let k_arg1 =
      T.var @@ HVar.fresh ~ty:(type_of_vars ~args:[] ~ret:tyvarB) ()

    (* Partially applies a combinator with arguments
        arguments:
          comb: original combinator with penalty for instantianting clause with it
          args: arguments with corresponding pentalties *)
    let partially_apply ~comb args =
      let orig_comb, penalty = comb in
      let rec aux acc = function 
        | [] -> []
        | (a,p) :: aas ->
          let acc = T.app acc [a] in
          (acc,p) :: aux acc aas in
      (orig_comb,penalty) :: aux orig_comb args

    let alpha = T.var tyvarA 
    let beta = T.var tyvarB
    let gamma = T.var tyvarC

    let partially_applied_s =
      partially_apply ~comb:(mk_s ~alpha ~beta ~gamma ~args:[], 1)
        [s_arg1, 2; s_arg2, 3]

    let partially_applied_b =
      partially_apply ~comb:(mk_b ~alpha ~beta ~gamma ~args:[], 1)
        [b_arg1, 2; b_arg2, 3]

    let partially_applied_c =
      partially_apply ~comb:(mk_c ~alpha ~beta ~gamma ~args:[], 1)
        [c_arg1, 2; c_arg2, 3]
    
    let partially_applied_k =
      partially_apply ~comb:(mk_k ~alpha ~beta ~args:[], 1)
        [k_arg1, 2]
    
    let partially_applied_i =
      [mk_i ~alpha ~args:[], 1]

    let partially_applied_combs =
      partially_applied_s @ partially_applied_b @ partially_applied_c @ 
      partially_applied_k @ partially_applied_i

    let instantiate_var_w_comb ~var =
      CCList.filter_map (fun (comb, penalty) ->
        try
          Some (Unif.FO.unify_syn (comb, 0) (var, 1), penalty)
        with Unif.Fail -> None
      ) partially_applied_combs


    let narrow_app_vars clause =
      let rule = Proof.Rule.mk "narrow applied variable" in
      let tags = [Proof.Tag.T_ho] in

      let ord = Env.ord () in 
      let eligible = C.Eligible.(res clause) in
      let lits = C.lits clause in
      (* do the inferences in which clause is passive (rewritten),
        so we consider both negative and positive literals *)
      Lits.fold_terms ~vars:(false) ~var_args:(true) ~fun_bodies:(false) 
                      ~subterms:true ~ord ~which:`Max ~eligible ~ty_args:false
      lits
      (* Variable has at least one arugment *)
      |> Iter.filter (fun (u_p, _) -> T.is_app_var u_p)
      |> Iter.flat_map_l (fun (u, u_pos) -> 
        (* variable names as in Ahmed's paper (unpublished) *)
        let var = T.head_term u in
        assert(T.is_var var);
        CCList.filter_map (fun (subst, comb_penalty) ->
          let renaming = Subst.Renaming.create () in
          let lit_idx, lit_pos = Lits.Pos.cut u_pos in
          let lit = Lit.apply_subst_no_simp renaming subst (lits.(lit_idx), 1) in
          if not (Lit.Pos.is_max_term ~ord lit lit_pos) ||
             not (CCBV.get (C.eligible_res (clause, 1) subst) lit_idx) then (
            None)
          else (
            let lits' = CCArray.to_list @@ Lits.apply_subst renaming subst (lits, 1) in
            let proof = 
              Proof.Step.inference ~rule ~tags
                [C.proof_parent_subst renaming (clause,1) subst] in
            let penalty = comb_penalty + C.penalty clause in
            let new_clause = C.create ~trail:(C.trail clause) ~penalty lits' proof in
            (* CCFormat.printf "success: @[%a@]@." Subst.pp subst; *)
            (* CCFormat.printf "res: @[%a@]@." C.pp new_clause; *)
            Some new_clause
          )) (instantiate_var_w_comb ~var))
        |> Iter.to_list
    
    let setup () =
      if E.flex_get k_enable_combinators then (
        E.add_clause_conversion enocde_stmt;
        E.add_unary_simplify comb_narrow;
        E.add_unary_inf "narrow applied variable" narrow_app_vars;
      )

end

let _enable_combinators = ref false

let extension =
  let lam2combs seq = seq in

  let register env =
    let module E = (val env : Env.S) in
    let module ET = Make(E) in
    E.flex_add k_enable_combinators !_enable_combinators;

    ET.setup ()
  in
  { Extensions.default with
      Extensions.name = "combinators";
      env_actions=[register];
      post_cnf_modifiers=[lam2combs];
  }

let () =
  Options.add_opts
    [ "--combinator-based-reasoning", Arg.Bool (fun v -> _enable_combinators := v), "enable / disable combinator based reasoning"];
  Extensions.register extension