
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Arbitrary generation of symbols} *)

open Libzipperposition

type 'a arbitrary = 'a QCheck.Arbitrary.t

val base : Type.t arbitrary
  (** Random base symbol *)

val ground : Type.t arbitrary
  (** Ground type *)

val default : Type.t arbitrary
  (** Any type (polymorphic) *)
