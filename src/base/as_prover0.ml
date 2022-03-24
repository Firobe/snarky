open Core_kernel

type ('a, 'f) t = ('a, 'f) Types.As_prover.t

module T = struct
  let map t ~f tbl =
    let x = t tbl in
    f x

  let bind t ~f tbl =
    let x = t tbl in
    f x tbl

  let return x _ = x

  let run t tbl = t tbl

  let get_state _tbl s = (s, s)

  let set_state s _tbl _ = (s, ())

  let modify_state f _tbl s = (f s, ())

  let map2 x y ~f tbl =
    let x = x tbl in
    let y = y tbl in
    f x y

  let read_var (v : 'var) : ('field, 'field) t = fun tbl -> tbl v

  let read' read (var : 'var) : ('value, 'field) t =
   fun tbl -> Typ_monads.Read.run (read var) tbl

  let read ({ read; _ } : ('var, 'value, 'field, _) Types.Typ.t) (var : 'var) :
      ('value, 'field) t =
    read' read var

  include Monad_let.Make2 (struct
    type nonrec ('a, 'e) t = ('a, 'e) t

    let map = `Custom map

    let bind = bind

    let return = return
  end)

  module Provider = struct
    (** The different ways to generate a value of type ['a] for a circuit
        witness over field ['f].

        This is one of:
        * a [Request], dispatching an ['a Request.t];
        * [Compute], running a computation to generate the value;
        * [Both], attempting to dispatch an ['a Request.t], and falling back to
          the computation if the request is unhandled or raises an exception.
    *)
    type nonrec ('a, 'f) t = (('a Request.t, 'f) t, ('a, 'f) t) Types.Provider.t

    open Types.Provider

    let run t stack tbl (handler : Request.Handler.t) =
      match t with
      | Request rc ->
          let r = run rc tbl in
          Request.Handler.run handler stack r
      | Compute c ->
          run c tbl
      | Both (rc, c) -> (
          let r = run rc tbl in
          match Request.Handler.run handler stack r with
          | exception _ ->
              run c tbl
          | x ->
              x )
  end

  module Handle = struct
    let value (t : ('var, 'value) Handle.t) : ('value, 'field) t =
     fun _ -> Option.value_exn t.value
  end
end

include T
