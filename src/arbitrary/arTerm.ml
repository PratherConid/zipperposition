
(* This file is free software, part of Zipperposition. See file "license" for more details. *)

(** {1 Arbitrary Typed Terms and Formulas} *)

open Libzipperposition

module QA = QCheck.Arbitrary
module T = FOTerm
module Sym = Symbol
module HOT = HOTerm

type 'a arbitrary = 'a QA.t

module PT = struct
  module PT = TypedSTerm

  let _const ~ty s = PT.const ~ty (ID.make s)

  let ty_term = PT.Ty.term
  let ty_fun1 = PT.Ty.([term] ==> term)
  let ty_fun2 = PT.Ty.([term; term] ==> term)
  let ty_fun3 = PT.Ty.([term; term; term] ==> term)

  let a = _const ~ty:ty_term "a"
  let b = _const ~ty:ty_term "b"
  let c = _const ~ty:ty_term "c"
  let d = _const ~ty:ty_term "d"
  let e = _const ~ty:ty_term "e"
  let f x y = PT.app ~ty:ty_term (_const ~ty:ty_fun2 "f") [x; y]
  let sum x y = PT.app ~ty:ty_term (_const ~ty:ty_fun2 "sum") [x; y]
  let g x = PT.app ~ty:ty_term (_const ~ty:ty_fun1 "g") [x]
  let h x = PT.app ~ty:ty_term (_const ~ty:ty_fun1 "h") [x]
  let ite x y z = PT.app ~ty:ty_term (_const ~ty:ty_fun3 "ite") [x; y; z]

  let ground =
    QA.(
      let base = among [a; b; c; d; e; ] in
      let t =
        fix ~max:6 ~base
          (fun sub ->
            choose
              [ lift2 f sub sub
              ; lift g sub
              ; lift h sub
              ; sub
              ; choose [lift2 sum sub sub; lift3 ite sub sub sub]
              ])
      in
      t)

  let map1_ f self = QA.( self 1 >>= function
    | [x] -> return (f x) | _ -> assert false
    )

  let map2_ f self = QA.( self 2 >>= function
    | [x;y] -> return (f x y) | _ -> assert false
    )

  let map3_ f self = QA.( self 3 >>= function
    | [x;y;z] -> return (f x y z) | _ -> assert false
    )

  let default_fuel fuel =
    let x = PT.var (Var.of_string ~ty:ty_term "X") in
    let y = PT.var (Var.of_string ~ty:ty_term "Y") in
    let z = PT.var (Var.of_string ~ty:ty_term "Z") in
    QA.(
      let t = fix_fuel
          [ `Base (return a)
          ; `Base (return b)
          ; `Base (return c)
          ; `Base (return d)
          ; `Base (return e)
          ; `Base (return x)
          ; `Base (return y)
          ; `Base (return z)
          ; `Rec (map2_ f)
          ; `Rec (map2_ sum)
          ; `Rec (map1_ g)
          ; `Rec (map1_ h)
          ; `Rec (map3_ ite)
          ]
      in
      retry (t fuel)
    )

  let default = QA.(int 40 >>= default_fuel)

  let ty_prop = PT.Ty.prop
  let ty_pred1 = PT.Ty.([term] ==> prop)
  let ty_pred2 = PT.Ty.([term; term] ==> prop)

  let p x y = PT.app ~ty:ty_prop (_const ~ty:ty_pred2 "p") [x; y]
  let q x = PT.app ~ty:ty_prop (_const ~ty:ty_pred1 "q") [x]
  let r x = PT.app ~ty:ty_prop (_const ~ty:ty_pred1 "r") [x]
  let s = PT.const ~ty:ty_prop (ID.make "s")

  let pred =
    let sub = default in
    QA.(
      choose
        [ lift2 p sub sub
        ; lift q sub
        ; lift r sub
        ; return s
        ]
    )

  module HO = struct
    let ground _ = assert false (* TODO *)

    let default _ = assert false (* TODO *)
  end
end

let ctx = FOTerm.Conv.create()

let default =
  QA.(PT.default >|= FOTerm.Conv.of_simple_term ctx)

let default_fuel f =
  QA.(PT.default_fuel f >|= FOTerm.Conv.of_simple_term ctx)

let ground =
  QA.(PT.ground >|= FOTerm.Conv.of_simple_term ctx)

let pred =
  QA.(PT.pred >|= FOTerm.Conv.of_simple_term ctx)

let pos t =
  let module PB = Position.Build in
  QA.(
    let rec recurse t pb st =
      let stop = return (PB.to_pos pb) in
      match T.view t with
      | T.App (_, [])
      | T.Const _
      | T.Var _
      | T.DB _ -> PB.to_pos pb
      | T.AppBuiltin (_, l)
      | T.App (_, l) ->
          choose (stop :: List.mapi (fun i t' -> recurse t' (PB.arg i pb)) l) st
    in
    recurse t PB.empty
  )

module HO = struct
  let ground =
    QA.(PT.HO.ground >|= HOTerm.of_simple_term)

  let default =
    QA.(PT.HO.default >|= HOTerm.of_simple_term)
end
