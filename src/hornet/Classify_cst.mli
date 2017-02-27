
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Classification of Constants} *)

open Logtk

type res =
  | Ty of Ind_ty.t
  | Cstor of Ind_ty.constructor * Ind_ty.t
  (* | Inductive_cst of Ind_cst.cst option *)
  | Projector of ID.t (** projector of some constructor (id: type) *)
  | DefinedCst of int (** (recursive) definition of given stratification level *)
  | Other

val classify : ID.t -> res
(** [classify id] returns the role [id] plays in inductive reasoning *)

val pp_res : res CCFormat.printer

val pp_signature : Signature.t CCFormat.printer
(** Print classification of signature *)

val prec_constr : [`partial] Precedence.Constr.t
(** Partial order on [ID.t], with:
    regular > constant > sub_constant > cstor *)

