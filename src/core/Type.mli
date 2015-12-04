(*
Copyright (c) 2013, Simon Cruanes
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 Types} *)

(** {2 Main Type representation}

    Types are represented using ScopedTerm, with kind Type. Therefore, they
    are hashconsed and scoped.

    Common representation of types, including higher-order
    and polymorphic types. All type variables
    are assumed to be universally quantified in the outermost possible
    scope (outside any other quantifier).

    See {!TypeInference} for inferring types from terms and formulas,
    and {!Signature} to associate types with symbols.

    TODO: think of a good way of representating AC operators (+, ...)
*)

type t = private ScopedTerm.t
(** Type is a subtype of the term structure
    (itself a subtype of ScopedTerm.t),
    with explicit conversion *)

type ty = t

type builtin = TType | Prop | Term

type view = private
  | Builtin of builtin
  | Var of t HVar.t
  | DB of int
  | App of ID.t * t list (** parametrized type *)
  | Fun of t list * t (** Function type (left to right, no left-nesting) *)
  | Record of (string*t) list * t HVar.t option (** Record type (+ variable) *)
  | Multiset of t
  | Forall of t (** explicit quantification using De Bruijn index *)

val view : t -> view
(** Type-centric view of the head of this type.
    @raise Assert_failure if the argument is not a type *)

include Interfaces.HASH with type t := t
include Interfaces.ORD with type t := t

val is_var : t -> bool
val is_bvar : t -> bool
val is_app : t -> bool
val is_fun : t -> bool
val is_forall : t -> bool
val is_record : t -> bool

(** {2 Constructors} *)

val tType : t
val prop : t
val term : t
val int : t
val rat : t

val var : t HVar.t -> t

val var_of_int : int -> t
(** Build a type variable. *)

val app : ID.t -> t list -> t
(** Parametrized type *)

val const : ID.t -> t
(** Constant sort *)

val arrow : t list -> t -> t
(** [arrow l r] is the type [l -> r]. *)

val record : (string*t) list -> rest:t HVar.t option -> t
(** Record type, with an optional extension *)

val forall : t -> t
(** Quantify over one type variable. Careful with the De Bruijn indices. *)

val bvar : int -> t
(** not documented. *)

val (@@) : ID.t -> t list -> t
(** [s @@ args] applies the sort [s] to arguments [args]. *)

val (==>) : t list -> t -> t
(** General function type. [l ==> x] is the same as [x] if [l]
    is empty. Invariant: the return type is never a function type. *)

val multiset : t -> t
(** Type of multiset *)

val of_term_unsafe : ScopedTerm.t -> t
(** {b NOTE}: this can break the invariants and make {!view} fail. Only
    use with caution. *)

val of_terms_unsafe : ScopedTerm.t list -> t list

(** {2 Containers} *)

module Set : CCSet.S with type elt = t
module Map : CCMap.S with type key = t
module Tbl : CCHashtbl.S with type key = t

module Seq : sig
  val vars : t -> t HVar.t Sequence.t
  val sub : t -> t Sequence.t (** Subterms *)
  val add_set : Set.t -> t Sequence.t -> Set.t
  val max_var : t HVar.t Sequence.t -> int
end

(** {2 Utils} *)

module VarSet : CCSet.S with type elt = t HVar.t
module VarMap : CCMap.S with type key = t HVar.t

val vars_set : VarSet.t -> t -> VarSet.t
(** Add the free variables to the given set *)

val vars : t -> t HVar.t list
(** List of free variables *)

val close_forall : t -> t
(** bind free variables *)

type arity_result =
  | Arity of int * int
  | NoArity

val arity : t -> arity_result
(** Number of arguments the type expects.
    If [arity ty] returns [Arity (a, b)] that means that it
    expects [a] arguments to be used as arguments of Forall, and
    [b] arguments to be used for function application. If
    it returns [NoArity] then the arity is unknown (variable) *)

val expected_args : t -> t list
(** Types expected as function argument by [ty]. The length of the
    list [expected_args ty] is the same as [snd (arity ty)]. *)

val is_ground : t -> bool
(** Is the type ground? (means that no {!Var} not {!BVar} occurs in it) *)

val size : t -> int
(** Size of type, in number of "nodes" *)

val depth : t -> int
(** Depth of the type (length of the longest path to some leaf)
    @since 0.5.3 *)

val open_fun : t -> (t list * t)
(** [open_fun ty] "unrolls" function arrows from the left, so that
    [open_fun (a -> (b -> (c -> d)))] returns [[a;b;c], d].
    @return the return type and the list of all its arguments *)

exception ApplyError of string
(** Error raised when {!apply} fails *)

val apply : t -> t list -> t
(** Given a function/forall type, and arguments, return the
    type that results from applying the function/forall to the arguments.
    No unification is done, types must check exactly.
    @raise ApplyError if the types do not match *)

val apply1 : t -> t -> t
(** [apply1 a b] is short for [apply a [b]]. *)

val apply_unsafe : t -> ScopedTerm.t list -> t
(** Similar to {!apply}, but assumes its arguments are well-formed
    types without more ado.
    @raise ApplyError if types do not match
    @raise Assert_failure if the arguments are not proper types *)

(** {2 IO} *)

include Interfaces.PRINT_DE_BRUIJN with type term := t and type t := t
include Interfaces.PRINT with type t := t
val pp_surrounded : t CCFormat.printer

(** {2 TPTP} specific printer and types *)

module TPTP : sig
  include Interfaces.PRINT_DE_BRUIJN with type term := t and type t := t
  include Interfaces.PRINT with type t := t

  (** {2 Basic types} *)

  val i : t       (** individuals *)
  val o : t       (** propositions *)

  val int : t     (** integers *)
  val rat : t     (** rationals *)
  val real : t    (** reals *)
end

(** {2 Conversions} *)

module Conv : sig
  type ctx
  val create : unit -> ctx
  val copy : ctx -> ctx
  val clear : ctx -> unit

  val of_simple_term : ctx -> TypedSTerm.t -> t option
  (** convert a simple typed term into a type. The term is assumed to be
        closed.
      @return an error message if the term is not a type
      @param ctx context used to map {!Var} to {!HVar} *)

  val to_simple_term :
    ?env:TypedSTerm.t Var.t DBEnv.t ->
    t -> TypedSTerm.t
  (** convert a type to a prolog term.
      @param env the current environement for De Bruijn indices *)
end
