open Core_kernel
open Bitstring_lib
open Tuple_lib

let local_function ~negate quad (b0, b1, b2) =
  let t = Quadruple.get quad (Four.of_bits_lsb (b0, b1)) in
  if b2 then negate t else t

module Make
    (Impl : Snark_intf.S) (Weierstrass_curve : sig
      type var = Impl.Field.Var.t * Impl.Field.Var.t

      type t [@@deriving eq]

      val add : t -> t -> t

      val zero : t

      module Checked : sig
        val constant : t -> var

        val add_unsafe :
             var
          -> var
          -> [ `I_thought_about_this_very_carefully of var ] Impl.Checked.t

        val add_known_unsafe :
             var
          -> t
          -> [ `I_thought_about_this_very_carefully of var ] Impl.Checked.t
      end
    end) (Params : sig
      open Impl

      val params : (Field.t * Field.t) Quadruple.t array
    end) : sig
  open Impl

  module Digest : sig
    type var = Field.Var.t

    module Unpacked : sig
      type var = Boolean.var Bitstring.Lsb_first.t

      type t = bool Bitstring.Lsb_first.t

      val typ : (var, t) Typ.t

      val project : var -> Field.Var.t

      val constant : t -> var
    end

    type t = Field.t

    val typ : (var, t) Typ.t

    val choose_preimage : var -> Unpacked.var Checked.t
  end

  module Section : sig
    module Acc : sig
      type t = [ `Var of Weierstrass_curve.var | `Value of Weierstrass_curve.t ]
    end

    type t

    val empty : t

    val disjoint_union_exn : t -> t -> t Checked.t

    val extend : t -> Boolean.var Triple.t list -> start:int -> t Checked.t

    val append : t -> Boolean.var Triple.t list -> t Checked.t

    val acc : t -> Weierstrass_curve.var

    val support : t -> Interval_union.t

    val create : acc:Acc.t -> support:Interval_union.t -> t

    val to_initial_segment_digest :
      t -> (Digest.var * [ `Length_in_triples of int ]) Or_error.t

    val to_initial_segment_digest_exn :
      t -> Digest.var * [ `Length_in_triples of int ]
  end

  val hash :
       init:int * Section.Acc.t
    -> Boolean.var Triple.t list
    -> Weierstrass_curve.var Checked.t

  val digest : Weierstrass_curve.var -> Digest.var
end = struct
  open Impl

  type affine_point = Field.t * Field.t

  let coords :
      affine_point Quadruple.t -> Field.t Quadruple.t * Field.t Quadruple.t =
   fun ((x1, y1), (x2, y2), (x3, y3), (x4, y4)) ->
    ((x1, x2, x3, x4), (y1, y2, y3, y4))

  let lookup ((s0, s1, s2) : Boolean.var Triple.t)
      (q : affine_point Quadruple.t) =
    let%bind s_and = Boolean.(s0 && s1) in
    let open Field.Checked in
    let lookup_one (a1, a2, a3, a4) =
      Field.Var.constant a1
      + (Field.(a2 - a1) * (s0 :> Field.Var.t))
      + (Field.(a3 - a1) * (s1 :> Field.Var.t))
      + (Field.(a4 + a1 - a2 - a3) * (s_and :> Field.Var.t))
    in
    let x_q, y_q = coords q in
    let x = lookup_one x_q in
    let%map y =
      let sign =
        (* sign = 1 if s2 = 0
           sign = -1 if s2 = 1 *)
        Field.Var.constant Field.one - (Field.of_int 2 * (s2 :> Field.Var.t))
      in
      Field.Checked.mul sign (lookup_one y_q)
    in
    (x, y)

  module Digest = struct
    let length_in_bits = Field.size_in_bits

    module Unpacked = struct
      open Bitstring.Lsb_first

      type var = Boolean.var t

      type t = bool Bitstring.Lsb_first.t

      let typ : (var, t) Typ.t =
        let there = to_list in
        let back = of_list in
        Typ.list Boolean.typ ~length:length_in_bits
        |> Typ.transport ~there ~back
        |> Typ.transport_var ~there ~back

      let project = Fn.compose Field.Var.project to_list

      let constant bs = of_list (List.map ~f:Boolean.var_of_value (to_list bs))
    end

    type var = Field.Var.t

    type t = Field.t

    let typ = Typ.field

    let choose_preimage x =
      with_label "Pedersen.Digest.choose_preimage"
        (Field.Checked.choose_preimage_var ~length:Field.size_in_bits x)
      |> Checked.map ~f:Bitstring.Lsb_first.of_list
  end

  let digest (x, _) = x

  (* The use of add_unsafe is acceptable in this context because getting this to
     hit a problematic case is tantamount to finding a collision in the pedersen hash. *)

  module Section = struct
    module Acc = struct
      type t = [ `Var of Weierstrass_curve.var | `Value of Weierstrass_curve.t ]

      let add (t1 : t) (t2 : t) =
        let open Let_syntax in
        match (t1, t2) with
        | `Var v1, `Var v2 ->
            (* This is acceptable as both v1 and v2 will be linear combinations of
               distinct sets of random group elements (as this is only called from disjoint_union_exn) *)
            let%map (`I_thought_about_this_very_carefully v) =
              Weierstrass_curve.Checked.add_unsafe v1 v2
            in
            `Var v
        | `Var v, `Value x | `Value x, `Var v ->
            if Weierstrass_curve.(equal zero x) then return (`Var v)
            else
              let%map (`I_thought_about_this_very_carefully v) =
                Weierstrass_curve.Checked.add_known_unsafe v x
              in
              `Var v
        | `Value x1, `Value x2 ->
            return (`Value (Weierstrass_curve.add x1 x2))

      let to_var = function
        | `Var v ->
            v
        | `Value x ->
            Weierstrass_curve.Checked.constant x
    end

    type t = { support : Interval_union.t; acc : Acc.t }

    let create ~acc ~support = { acc; support }

    let empty =
      { acc = `Value Weierstrass_curve.zero; support = Interval_union.empty }

    let acc t = Acc.to_var t.acc

    let support t = t.support

    let disjoint_union_exn t1 t2 =
      let support = Interval_union.disjoint_union_exn t1.support t2.support in
      let%map acc = Acc.add t1.acc t2.acc in
      { support; acc }

    let to_initial_segment_digest t =
      let open Or_error.Let_syntax in
      let%bind a, b = Interval_union.to_interval t.support in
      let%map () =
        if a <> 0 then
          Or_error.errorf
            "to_initial_segment: Left endpoint was not zero interval: (%d, %d)"
            a b
        else Ok ()
      in
      (digest (acc t), `Length_in_triples b)

    let to_initial_segment_digest_exn t =
      Or_error.ok_exn (to_initial_segment_digest t)

    let get_term i bits = lookup bits Params.params.(i)

    let extend t triples ~start =
      let open Let_syntax in
      let hash offset init xs =
        Checked.List.foldi xs ~init ~f:(fun i acc x ->
            (* This is acceptable because [get_term (offset+i) x] is a linear combination
               of random elements not involved in the calculation of acc *)
            let%map (`I_thought_about_this_very_carefully acc) =
              get_term (offset + i) x
              >>= Weierstrass_curve.Checked.add_unsafe acc
            in
            acc)
      in
      match triples with
      | [] ->
          return t
      | x :: xs ->
          let support =
            Interval_union.disjoint_union_exn t.support
              (Interval_union.of_interval (start, start + List.length triples))
          in
          let%map acc =
            match t.acc with
            | `Value v ->
                let%bind init_term = get_term start x in
                let%bind init =
                  if Weierstrass_curve.(equal zero v) then return init_term
                  else
                    (* This is acceptable because [t.acc] is a pedersen hash on a domain
                              disjoint from the random group elements used in computing [init_term]. *)
                    let%map (`I_thought_about_this_very_carefully r) =
                      Weierstrass_curve.Checked.add_known_unsafe init_term v
                    in
                    r
                in
                hash (start + 1) init xs
            | `Var v ->
                hash start v (x :: xs)
          in
          { support; acc = `Var acc }

    let append t triples =
      let start =
        Option.value (Interval_union.right_endpoint t.support) ~default:0
      in
      extend t triples ~start
  end

  let hash ~init:(start, acc) triples =
    let open Checked.Let_syntax in
    let%map { acc; _ } =
      Section.extend { acc; support = Interval_union.empty } triples ~start
    in
    match acc with `Var acc -> acc | `Value _ -> assert false
end
