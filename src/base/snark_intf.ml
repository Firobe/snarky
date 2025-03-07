module Bignum_bigint = Bigint
open Core_kernel
module Constraint0 = Constraint
module Boolean0 = Boolean
module Typ0 = Typ
module As_prover0 = As_prover

(** Yojson-compatible JSON type. *)
type 'a json =
  [> `String of string
  | `Assoc of (string * 'a json) list
  | `List of 'a json list ]
  as
  'a

(** The base interface to Snarky. *)
module type Basic = sig
  (** The finite field over which the R1CS operates. *)
  type field

  (** The rank-1 constraint system used by this instance. See
      {!module:Backend_intf.S.R1CS_constraint_system}. *)
  module R1CS_constraint_system : sig
    type t

    val digest : t -> Md5.t

    (** Convert a basic constraint into a JSON representation.

        This representation is compatible with the Yojson library, which can be
        used to print JSON to the screen, write it to a file, etc.
    *)
    val to_json : t -> 'a json
  end

  (** Variables in the R1CS. *)
  module Var : sig
    include Comparable.S

    val create : int -> t

    val index : t -> int
  end

  module Bigint : sig
    include Snarky_intf.Bigint_intf.Extended with type field := field

    val of_bignum_bigint : Bignum_bigint.t -> t

    val to_bignum_bigint : t -> Bignum_bigint.t
  end

  (** Rank-1 constraints over {!type:Var.t}s. *)
  module rec Constraint : sig
    (** The type of constraints.
        In the proof system, every constraint is a rank-1 constraint; that is,
        the constraint takes the form [a * b = c] for some [a], [b] and [c]
        which are made up of some linear combination of {!type:Field.Var.t}s.

        For example, a constraint could be [(w + 2*x) * (y + z) = a + b], where
        [w], [x], [y], [z], [a], and [b] are field variables.
        Note that a linear combination is the result of adding together some of
        these variables, each multiplied by a field constant ({!type:Field.t});
        any time we want to multiply our *variables*, we need to add a new
        rank-1 constraint.
    *)
    type t = (Field.Var.t, Field.t) Constraint0.t

    type 'k with_constraint_args = ?label:string -> 'k

    (** A constraint that asserts that the field variable is a boolean: either
        {!val:Field.zero} or {!val:Field.one}.
    *)
    val boolean : (Field.Var.t -> t) with_constraint_args

    (** A constraint that asserts that the field variable arguments are equal.
    *)
    val equal : (Field.Var.t -> Field.Var.t -> t) with_constraint_args

    (** A bare rank-1 constraint. *)
    val r1cs :
      (Field.Var.t -> Field.Var.t -> Field.Var.t -> t) with_constraint_args

    (** A constraint that asserts that the first variable squares to the
        second, ie. [square x y] => [x*x = y] within the field.
    *)
    val square : (Field.Var.t -> Field.Var.t -> t) with_constraint_args
  end

  (** The data specification for checked computations. *)
  and Data_spec : sig
    (** A list of {!type:Typ.t} values, describing the inputs to a checked
        computation. The type [('r_var, 'r_value, 'k_var, 'k_value) t]
        represents
        - ['k_value] is the OCaml type of the computation
        - ['r_value] is the OCaml type of the result
        - ['k_var] is the type of the computation within the R1CS
        - ['k_value] is the type of the result within the R1CS.

        This functions the same as OCaml's default list type:
{[
  Data_spec.[typ1; typ2; typ3]

  Data_spec.(typ1 :: typs)

  let open Data_spec in
  [typ1; typ2; typ3; typ4; typ5]

  let open Data_spec in
  typ1 :: typ2 :: typs

]}
        all function as you would expect.
    *)
    type ('r_var, 'r_value, 'k_var, 'k_value) t =
      ('r_var, 'r_value, 'k_var, 'k_value, field) Typ0.Data_spec.t

    (** [size [typ1; ...; typn]] returns the number of {!type:Var.t} variables
        allocated by allocating [typ1], followed by [typ2], etc. *)
    val size : _ t -> int

    include module type of Typ0.Data_spec0
  end

  (** Mappings from OCaml types to R1CS variables and constraints. *)
  and Typ : sig
    (** The type [('var, 'value) t] describes a mapping from the OCaml type
        ['value] to a type representing the value using R1CS variables
        (['var]).
        This description includes
        - a {!type:Store.t} for storing ['value]s as ['var]s
        - a {!type:Alloc.t} for creating a ['var] when we don't know what values
          it should contain yet
        - a {!type:Read.t} for reading the contents of the ['var] back out as a
          ['value] in {!module:As_prover} blocks
        - a {!type:Checked.t} for asserting constraints on the ['var] -- for
          example, that a [Boolean.t] is either a {!val:Field.zero} or a
          {!val:Field.one}.
    *)
    type ('var, 'value) t = ('var, 'value, Field.t, unit Checked.t) Types.Typ.t

    (** Basic instances: *)

    val unit : (unit, unit) t

    val field : (Field.Var.t, field) t

    (** Common constructors: *)

    val tuple2 :
         ('var1, 'value1) t
      -> ('var2, 'value2) t
      -> ('var1 * 'var2, 'value1 * 'value2) t

    (** synonym for {!val:tuple2} *)
    val ( * ) :
         ('var1, 'value1) t
      -> ('var2, 'value2) t
      -> ('var1 * 'var2, 'value1 * 'value2) t

    val tuple3 :
         ('var1, 'value1) t
      -> ('var2, 'value2) t
      -> ('var3, 'value3) t
      -> ('var1 * 'var2 * 'var3, 'value1 * 'value2 * 'value3) t

    (** [list ~length typ] describes how to convert between a ['value list] and
        a ['var list], given a description of how to convert between a ['value]
        and a ['var].

        [length] must be the length of the lists that are converted. This value
        must be constant for every use; otherwise the constraint system may use
        a different number of variables depending on the data given.

        Passing a list of the wrong length throws an error.
    *)
    val list : length:int -> ('var, 'value) t -> ('var list, 'value list) t

    (** [array ~length typ] describes how to convert between a ['value array]
        and a ['var array], given a description of how to convert between a
        ['value] and a ['var].

        [length] must be the length of the arrays that are converted. This
        value must be constant for every use; otherwise the constraint system
        may use a different number of variables depending on the data given.

        Passing an array of the wrong length throws an error.
    *)
    val array : length:int -> ('var, 'value) t -> ('var array, 'value array) t

    (** Unpack a {!type:Data_spec.t} list to a {!type:t}. The return value relates
        a polymorphic list of OCaml types to a polymorphic list of R1CS types. *)
    val hlist :
         (unit, unit, 'k_var, 'k_value) Data_spec.t
      -> ((unit, 'k_var) H_list.t, (unit, 'k_value) H_list.t) t

    (** Convert relationships over
        {{:https://en.wikipedia.org/wiki/Isomorphism}isomorphic} types: *)

    val transport :
         ('var, 'value1) t
      -> there:('value2 -> 'value1)
      -> back:('value1 -> 'value2)
      -> ('var, 'value2) t

    val transport_var :
         ('var1, 'value) t
      -> there:('var2 -> 'var1)
      -> back:('var1 -> 'var2)
      -> ('var2, 'value) t

    (** A specialised version of {!val:transport}/{!val:transport_var} that
        describes the relationship between ['var] and ['value] in terms of a
        {!type:Data_spec.t}.
    *)
    val of_hlistable :
         (unit, unit, 'k_var, 'k_value) Data_spec.t
      -> var_to_hlist:('var -> (unit, 'k_var) H_list.t)
      -> var_of_hlist:((unit, 'k_var) H_list.t -> 'var)
      -> value_to_hlist:('value -> (unit, 'k_value) H_list.t)
      -> value_of_hlist:((unit, 'k_value) H_list.t -> 'value)
      -> ('var, 'value) t

    (** [Typ.t]s that make it easier to write a [Typ.t] for a mix of R1CS data
        and normal OCaml data.

        Using this module is not recommended.
    *)
    module Internal : sig
      (** A do-nothing [Typ.t] that returns the input value for all modes. This
          may be used to convert objects from the [Checked] world into and
          through [As_prover] blocks.

          This is the dual of [ref], which allows [OCaml] values from
          [As_prover] blocks to pass through the [Checked] world.

          Note: Reading or writing using this [Typ.t] will assert that the
          argument and the value stored are physically equal -- ie. that they
          refer to the same object.
      *)
      val snarkless : 'a -> ('a, 'a) t

      (** A [Typ.t] for marshalling OCaml values generated in [As_prover]
          blocks, while keeping them opaque to the [Checked] world.

          This is the dual of [snarkless], which allows [OCaml] values from the
          [Checked] world to pass through [As_prover] blocks.
    *)
      val ref : unit -> ('a As_prover.Ref.t, 'a) t
    end

    module type S =
      Typ0.Intf.S
        with type field := Field.t
         and type field_var := Field.Var.t
         and type _ checked = unit Checked.t

    val mk_typ :
         (module S with type Var.t = 'var and type Value.t = 'value)
      -> ('var, 'value) t

    include module type of Types.Typ.T
  end

  (** Representation of booleans within a field.

      This representation ties the value of [true] to {!val:Field.one} and
      [false] to {!val:Field.zero}, adding a check in {!val:Boolean.typ} to
      ensure that these are the only vales. *)
  and Boolean : sig
    (** The type that stores booleans as R1CS variables. *)
    type var = Field.Var.t Boolean0.t

    type value = bool

    (** An R1CS variable containing {!val:Field.one}, representing [true]. *)
    val true_ : var

    (** An R1CS variable containing {!val:Field.zero}, representing [false]. *)
    val false_ : var

    (** [if_ b ~then_ ~else_] returns [then_] if [b] is true, or [else_]
        otherwise.
    *)
    val if_ : var -> then_:var -> else_:var -> var Checked.t

    (** Negate a boolean value *)
    val not : var -> var

    (** Boolean and *)
    val ( && ) : var -> var -> var Checked.t

    (** Boolean and, non-aliasing to [bool] operator. *)
    val ( &&& ) : var -> var -> var Checked.t

    (** Boolean or *)
    val ( || ) : var -> var -> var Checked.t

    (** Boolean or, non-aliasing to [bool] operator. *)
    val ( ||| ) : var -> var -> var Checked.t

    (** Boolean xor (exclusive-or) *)
    val ( lxor ) : var -> var -> var Checked.t

    (** Returns [true] if any value in the list is true, false otherwise. *)
    val any : var list -> var Checked.t

    (** Returns [true] if all value in the list are true, false otherwise. *)
    val all : var list -> var Checked.t

    (** Convert a value in a field to a boolean, adding checks to the R1CS that
       it is a valid boolean value. *)
    val of_field : Field.Var.t -> var Checked.t

    (** Convert an OCaml [bool] into a R1CS variable representing the same
        value. *)
    val var_of_value : value -> var

    (** The relationship between {!val:var} and {!val:value}, with a check that
        the value is valid (ie. {!val:Field.zero} or {!val:Field.one}). *)
    val typ : (var, value) Typ.t

    (** {!val:typ} without a validity check for the underlying field value. *)
    val typ_unchecked : (var, value) Typ.t

    val equal : var -> var -> var Checked.t

    (** Build trees representing boolean expressions. *)
    module Expr : sig
      (** Expression trees. *)
      type t

      val ( ! ) : var -> t

      val ( && ) : t -> t -> t

      val ( &&& ) : t -> t -> t

      val ( || ) : t -> t -> t

      val ( ||| ) : t -> t -> t

      val any : t list -> t

      val all : t list -> t

      val not : t -> t

      (** Evaluate the expression tree. *)
      val eval : t -> var Checked.t

      val assert_ : t -> unit Checked.t
    end

    module Unsafe : sig
      val of_cvar : Field.Var.t -> var
    end

    module Assert : sig
      val ( = ) : Boolean.var -> Boolean.var -> unit Checked.t

      val is_true : Boolean.var -> unit Checked.t

      val any : var list -> unit Checked.t

      val all : var list -> unit Checked.t

      val exactly_one : var list -> unit Checked.t
    end

    module Array : sig
      val any : var array -> var Checked.t

      val all : var array -> var Checked.t

      module Assert : sig
        val any : var array -> unit Checked.t

        val all : var array -> unit Checked.t
      end
    end
  end

  (** Checked computations.

      These are the values used to generate an R1CS for a computation. *)
  and Checked : sig
    (** [('ret, 'state) t] represents a computation ['state -> 'ret] that can
        be compiled into an R1CS.

        We form a
        {{:https://en.wikipedia.org/wiki/Monad_(functional_programming)}monad}
        over this type, which allows us to work inside the checked function to
        do further checked computations. For example (using
        {{:https://github.com/janestreet/ppx_let}monad let-syntax}):
{[
let multiply3 (x : Field.Var.t) (y : Field.Var.t) (z : Field.Var.t)
  : (Field.Var.t) Checked.t =
  open Checked.Let_syntax in
  let%bind x_times_y = Field.Checked.mul x y in
  Field.Checked.mul x_times_y z
]}
    *)

    type run_state = Field.t Run_state.t

    include Monad_let.S with type 'a t = ('a, Field.t) Types.Checked.t

    module List :
      Monad_sequence.S
        with type 'a monad := 'a t
         and type 'a t = 'a list
         and type boolean := Boolean.var

    module Array :
      Monad_sequence.S
        with type 'a monad := 'a t
         and type 'a t = 'a array
         and type boolean := Boolean.var

    (** [Choose_preimage] is the request issued by
        {!val:Field.Checked.choose_preimage_var} before falling back to its
        default implementation. You can respond to this request to override the
        default behaviour.

        See {!module:Request} for more information on requests. *)
    type _ Request.t += Choose_preimage : field * int -> bool list Request.t
  end

  and Field : sig
    (** The finite field over which the R1CS operates.
        Values may be between 0 and {!val:size}. *)
    type t = field [@@deriving bin_io, sexp, hash, compare]

    (** A generator for Quickcheck tests. *)
    val gen : t Core_kernel.Quickcheck.Generator.t

    (** A generator for Quickcheck tests within specified inclusive bounds *)
    val gen_incl : t -> t -> t Core_kernel.Quickcheck.Generator.t

    (** A uniform generator for Quickcheck tests. *)
    val gen_uniform : t Core_kernel.Quickcheck.Generator.t

    (** A uniform Quickcheck generator within specified inclusive bounds *)
    val gen_uniform_incl : t -> t -> t Core_kernel.Quickcheck.Generator.t

    include Snarky_intf.Field.Extended with type t := t

    include Stringable.S with type t := t

    (** The number at which values in the field wrap back around to 0. *)
    val size : Bignum_bigint.t

    (** Convert a field element into its constituent bits. *)
    val unpack : t -> bool list

    (** Convert a list of bits into a field element. This is the inverse of
        unpack.
    *)
    val project : bool list -> t

    (** [project], but slow. Exposed for benchmarks. *)
    val project_reference : bool list -> t

    (** Get the least significant bit of a field element. *)
    val parity : t -> bool

    type var' = Var.t

    module Var : sig
      (** The type that stores booleans as R1CS variables. *)
      type t = field Cvar.t

      (** For debug purposes *)
      val length : t -> int

      val var_indices : t -> int list

      (** Convert a {!type:t} value to its constituent constant and a list of
          scaled R1CS variables. *)
      val to_constant_and_terms : t -> field option * (field * Var.t) list

      (** [constant x] creates a new R1CS variable containing the constant
          field element [x]. *)
      val constant : field -> t

      (** [to_constant x] returns [Some f] if x holds only the constant field
          element [f]. Otherwise, it returns [None].
      *)
      val to_constant : t -> field option

      (** [linear_combination [(f1, x1);...;(fn, xn)]] returns the result of
          calculating [f1 * x1 + f2 * x2 + ... + fn * xn].
          This does not add a new constraint; see {!type:Constraint.t} for more
          information.
      *)
      val linear_combination : (field * t) list -> t

      (** [sum l] returns the sum of all R1CS variables in [l].

          If the result would be greater than or equal to {!val:Field.size}
          then the value will overflow to be less than {!val:Field.size}.
      *)
      val sum : t list -> t

      (** [add x y] returns the result of adding the R1CS variables [x] and
          [y].

          If the result would be greater than or equal to {!val:Field.size}
          then the value will overflow to be less than {!val:Field.size}.
      *)
      val add : t -> t -> t

      (** [negate x] returns the additive inverse of x as a field eleement
      *)
      val negate : t -> t

      (** [sub x y] returns the result of subtracting the R1CS variables [x]
          and [y].

          If the result would be less than 0 then the value will underflow
          to be between 0 and {!val:Field.size}.
      *)
      val sub : t -> t -> t

      (** [scale x f] returns the result of multiplying the R1CS variable [x]
          by the constant field element [f].

          If the result would be greater than or equal to {!val:Field.size}
          then the value will overflow to be less than {!val:Field.size}.
      *)
      val scale : t -> field -> t

      (** Convert a list of bits into a field element.

          [project [b1;...;bn] = b1 + 2*b2 + 4*b3 + ... + 2^(n-1) * bn]

          If the result would be greater than or equal to {!val:Field.size}
          then the value will overflow to be less than {!val:Field.size}.
      *)
      val project : Boolean.var list -> t

      (** Convert a list of bits into a field element.

          [pack [b1;...;bn] = b1 + 2*b2 + 4*b3 + ... + 2^(n-1) * bn]

          This will raise an assertion error if the length of the list is not
          strictly less than number of bits in {!val:Field.size}.

          Use [project] if you know that the list represents a value less than
          {!val:Field.size} but where the number of bits may be the maximum, or
          where overflow is appropriate.
      *)
      val pack : Boolean.var list -> t
    end

    module Checked : sig
      (** [mul x y] returns the result of multiplying the R1CS variables [x]
          and [y].

          If the result would be greater than or equal to {!val:Field.size}
          then the value will overflow to be less than {!val:Field.size}.
      *)
      val mul : Var.t -> Var.t -> Var.t Checked.t

      (** [square x] returns the result of multiplying the R1CS variables [x]
          by itself.

          If the result would be greater than or equal to {!val:Field.size}
          then the value will overflow to be less than {!val:Field.size}.
      *)
      val square : Var.t -> Var.t Checked.t

      (** [div x y] returns the result of dividing the R1CS variable [x] by
          [y].

          If [x] is not an integer multiple of [y], the result could be any
          value; it is equivalent to computing [mul x (inv y)].

          If [y] is 0, this raises a [Failure].
      *)
      val div : Var.t -> Var.t -> Var.t Checked.t

      (** [inv x] returns the value such that [mul x (inv x) = 1].

          If [x] is 0, this raises a [Failure].
      *)
      val inv : Var.t -> Var.t Checked.t

      (** [is_square x] checks if [x] is a square in the field.
      *)
      val is_square : Var.t -> Boolean.var Checked.t

      (** [sqrt x] is the square root of [x] if [x] is a square. If not, this
          raises a [Failure]
      *)
      val sqrt : Var.t -> Var.t Checked.t

      (** If [x] is a square in the field and [(y, b) = sqrt_check x],
        If b = true, then x is a square and y is sqrt(x)
        If b = false, then x is not a square y is a value which is not meaningful. *)
      val sqrt_check : Var.t -> (Var.t * Boolean.var) Checked.t

      (** [equal x y] returns a R1CS variable containing the value [true] if
          the R1CS variables [x] and [y] are equal, or [false] otherwise.
      *)
      val equal : Var.t -> Var.t -> Boolean.var Checked.t

      (** [unpack x ~length] returns a list of R1CS variables containing the
          [length] lowest bits of [x]. If [length] is greater than the number
          of bits in {!val:Field.size} then this raises a [Failure].

          For example,
          - [unpack 8 ~length:4 = [0; 0; 0; 1]]
          - [unpack 9 ~length:3 = [1; 0; 0]]
          - [unpack 9 ~length:5 = [1; 0; 0; 1; 0]]
      *)
      val unpack : Var.t -> length:int -> Boolean.var list Checked.t

      (** [unpack x ~length = (unpack x ~length, `Success success)], where
          [success] is an R1CS variable containing [true] if the returned bits
          represent [x], and [false] otherwise.

          If [length] is greater than the number of bits in {!val:Field.size}
          then this raises a [Failure].
      *)
      val unpack_flagged :
           Var.t
        -> length:int
        -> (Boolean.var list * [ `Success of Boolean.var ]) Checked.t

      (** [unpack x ~length] returns a list of R1CS variables containing the
          bits of [x].
      *)
      val unpack_full :
        Var.t -> Boolean.var Bitstring_lib.Bitstring.Lsb_first.t Checked.t

      (** Get the least significant bit of a field element [x].
          Pass a value for [length] if you know that [x] fits in [length] many bits.
      *)
      val parity : ?length:int -> Var.t -> Boolean.var Checked.t

      (** [unpack x ~length] returns a list of R1CS variables containing the
          [length] lowest bits of [x].
      *)
      val choose_preimage_var :
        Var.t -> length:int -> Boolean.var list Checked.t

      (** The type of results from checked comparisons, stored as boolean R1CS
          variables.
      *)
      type comparison_result =
        { less : Boolean.var; less_or_equal : Boolean.var }

      (** [compare ~bit_length x y] compares the [bit_length] lowest bits of
          [x] and [y]. [bit_length] must be [<= size_in_bits - 2].

          This requires converting an R1CS variable into a list of bits.

          WARNING: [x] and [y] must be known to be less than [2^{bit_length}]
                   already, otherwise this function may not return the correct
                   result.
      *)
      val compare :
        bit_length:int -> Var.t -> Var.t -> comparison_result Checked.t

      (** [if_ b ~then_ ~else_] returns [then_] if [b] is true, or [else_]
          otherwise.
      *)
      val if_ : Boolean.var -> then_:Var.t -> else_:Var.t -> Var.t Checked.t

      (** Infix notations for the basic field operations. *)

      val ( + ) : Var.t -> Var.t -> Var.t

      val ( - ) : Var.t -> Var.t -> Var.t

      val ( * ) : field -> Var.t -> Var.t

      module Unsafe : sig
        val of_index : int -> Var.t
      end

      (** Assertions *)
      module Assert : sig
        val lte : bit_length:int -> Var.t -> Var.t -> unit Checked.t

        val gte : bit_length:int -> Var.t -> Var.t -> unit Checked.t

        val lt : bit_length:int -> Var.t -> Var.t -> unit Checked.t

        val gt : bit_length:int -> Var.t -> Var.t -> unit Checked.t

        val not_equal : Var.t -> Var.t -> unit Checked.t

        val equal : Var.t -> Var.t -> unit Checked.t

        val non_zero : Var.t -> unit Checked.t
      end
    end

    (** Describes how to convert between {!type:t} and {!type:Var.t} values. *)
    val typ : (Var.t, t) Typ.t
  end

  (** Code that can be run by the prover only, using 'superpowers' like looking
      at the contents of R1CS variables and creating new variables from other
      OCaml values.
  *)
  and As_prover : sig
    (** An [('a) t] value generates a value of type ['a].

        This type specialises the {!type:As_prover.t} type for the backend's
        particular field and variable type. *)
    type 'a t = ('a, field) As_prover0.t

    type 'a as_prover = 'a t

    (** Mutable references for use by the prover in a checked computation. *)
    module Ref : sig
      (** A mutable reference to an ['a] value, which may be used in checked
          computations. *)
      type 'a t

      val create : 'a as_prover -> 'a t Checked.t

      val get : 'a t -> 'a as_prover

      val set : 'a t -> 'a -> unit as_prover
    end

    include Monad_let.S with type 'a t := 'a t

    (** Combine 2 {!type:As_prover.t} blocks using another function. *)
    val map2 : 'a t -> 'b t -> f:('a -> 'b -> 'c) -> 'c t

    (** Read the contents of a R1CS variable representing a single field
        element. *)
    val read_var : Field.Var.t -> field t

    (** [read typ x] reads the contents of the R1CS variables in [x] to create
        an OCaml variable of type ['value], according to the description given
        by [typ].
    *)
    val read : ('var, 'value) Typ.t -> 'var -> 'value t
  end

  (** The complete set of inputs needed to generate a zero-knowledge proof. *)
  and Proof_inputs : sig
    type t =
      { public_inputs : Field.Vector.t; auxiliary_inputs : Field.Vector.t }
  end

  module Let_syntax : Monad_let.Syntax2 with type ('a, 's) t := 'a Checked.t

  (** Utility functions for dealing with lists of bits in the R1CS. *)
  module Bitstring_checked : sig
    type t = Boolean.var list

    val equal : t -> t -> Boolean.var Checked.t

    (** Equivalent to [equal], but avoids computing field elements to represent
        chunks of the list when not necessary.

        NOTE: This will do extra (wasted) work before falling back to the
              behaviour of [equal] when the values are not equal.
    *)
    val equal_expect_true : t -> t -> Boolean.var Checked.t

    val lt_value :
         Boolean.var Bitstring_lib.Bitstring.Msb_first.t
      -> bool Bitstring_lib.Bitstring.Msb_first.t
      -> Boolean.var Checked.t

    module Assert : sig
      val equal : t -> t -> unit Checked.t
    end
  end

  (** Representation of an R1CS value and an OCaml value (if running as the
      prover) together.
  *)
  module Handle : sig
    type ('var, 'value) t

    (** Get the value of a handle as the prover. *)
    val value : (_, 'value) t -> 'value As_prover.t

    (** Get the R1CS representation of a value. *)
    val var : ('var, _) t -> 'var
  end

  (** Utility functions for calling single checked computations. *)
  module Runner : sig
    type state

    val run : 'a Checked.t -> state -> state * 'a
  end

  type response = Request.response

  val unhandled : response

  (** The argument type for request handlers.

{[
  type _ Request.t += My_request : 'a list -> 'a Request.t

  let handled (c : ('a) Checked.t) : ('a) Checked.t =
    handle (fun (With {request; respond}) ->
      match request with
      | My_request l ->
        let x = (* Do something with l to create a single value. *) in
        respond (Provide x)
      | _ -> unhandled )
]}
  *)
  type request = Request.request =
    | With :
        { request : 'a Request.t; respond : 'a Request.Response.t -> response }
        -> request

  (** The type of handlers. *)
  module Handler : sig
    type t = request -> response
  end

  (** Utility functions for running different representations of checked
      computations using a standard interface.
  *)
  module Perform : sig
    type ('a, 't) t = 't -> Runner.state -> Runner.state * 'a

    val constraint_system :
         run:('a, 't) t
      -> exposing:('t, _, 'k_var, _) Data_spec.t
      -> return_typ:('a, _) Typ.t
      -> 'k_var
      -> R1CS_constraint_system.t

    val generate_witness :
         run:('a, 't) t
      -> ('t, Proof_inputs.t, 'k_var, 'k_value) Data_spec.t
      -> return_typ:('a, _) Typ.t
      -> 'k_var
      -> 'k_value

    val generate_witness_conv :
         run:('a, 't) t
      -> f:(Proof_inputs.t -> 'public_output -> 'out)
      -> ('t, 'out, 'k_var, 'k_value) Data_spec.t
      -> return_typ:('a, 'public_output) Typ.t
      -> 'k_var
      -> 'k_value

    val run_unchecked : run:('a, 't) t -> 't -> 'a

    val run_and_check : run:('a As_prover.t, 't) t -> 't -> 'a Or_error.t

    val check : run:('a, 't) t -> 't -> unit Or_error.t
  end

  (** Add a constraint to the constraint system, optionally with the label
      given by [label]. *)
  val assert_ : ?label:string -> Constraint.t -> unit Checked.t

  (** Add all of the constraints in the list to the constraint system,
      optionally with the label given by [label].
  *)
  val assert_all : ?label:string -> Constraint.t list -> unit Checked.t

  (** Add a rank-1 constraint to the constraint system, optionally with the
      label given by [label].

      See {!val:Constraint.r1cs} for more information on rank-1 constraints.
  *)
  val assert_r1cs :
    ?label:string -> Field.Var.t -> Field.Var.t -> Field.Var.t -> unit Checked.t

  (** Add a 'square' constraint to the constraint system, optionally with the
      label given by [label].

      See {!val:Constraint.square} for more information.
  *)
  val assert_square :
    ?label:string -> Field.Var.t -> Field.Var.t -> unit Checked.t

  (** Run an {!module:As_prover} block. *)
  val as_prover : unit As_prover.t -> unit Checked.t

  (** Lazily evaluate a checked computation.

      Any constraints within the checked computation are not added to the
      constraint system unless the lazy value is forced.
  *)
  val mk_lazy : 'a Checked.t -> 'a Lazy.t Checked.t

  (** Internal: read the value of the next unused auxiliary input index. *)
  val next_auxiliary : int Checked.t

  (** [request_witness typ create_request] runs the [create_request]
      {!type:As_prover.t} block to generate a {!type:Request.t}.

      This allows us to introduce values into the R1CS without passing them as
      public inputs.

      If no handler for the request is attached by {!val:handle}, this raises
      a [Failure].
  *)
  val request_witness :
    ('var, 'value) Typ.t -> 'value Request.t As_prover.t -> 'var Checked.t

  (** Like {!val:request_witness}, but the request doesn't return any usable
      value.
  *)
  val perform : unit Request.t As_prover.t -> unit Checked.t

  (** Like {!val:request_witness}, but generates the request without using
      any {!module:As_prover} 'superpowers'.

      The argument [such_that] allows adding extra constraints on the returned
      value.

      (* TODO: Come up with a better name for this in relation to the above *)
  *)
  val request :
       ?such_that:('var -> unit Checked.t)
    -> ('var, 'value) Typ.t
    -> 'value Request.t
    -> 'var Checked.t

  (** Introduce a value into the R1CS.
      - The [request] argument functions like {!val:request_witness}, creating
        a request and returning the result.
      - If no [request] argument is given, or if the [request] isn't handled,
        then [compute] is run to create a value.

      If [compute] is not given and [request] fails/is also not given, then
      this function raises a [Failure].
  *)
  val exists :
       ?request:'value Request.t As_prover.t
    -> ?compute:'value As_prover.t
    -> ('var, 'value) Typ.t
    -> 'var Checked.t

  (** Like {!val:exists}, but returns a {!type:Handle.t}.

      This persists the OCaml value of the result, which is stored unchanged in
      the {!type:Handle.t} and can be recalled in later {!module:As_prover}
      blocks using {!val:Handle.value}.
  *)
  val exists_handle :
       ?request:'value Request.t As_prover.t
    -> ?compute:'value As_prover.t
    -> ('var, 'value) Typ.t
    -> ('var, 'value) Handle.t Checked.t

  (** Add a request handler to the checked computation, to be used by
      {!val:request_witness}, {!val:perform}, {!val:request} or {!val:exists}.
  *)
  val handle : 'a Checked.t -> Handler.t -> 'a Checked.t

  (** Generate a handler using the {!module:As_prover} 'superpowers', and use
      it for {!val:request_witness}, {!val:perform}, {!val:request} or
      {!val:exists} calls in the wrapped checked computation.
  *)
  val handle_as_prover : 'a Checked.t -> Handler.t As_prover.t -> 'a Checked.t

  (** [if_ b ~then_ ~else_] returns [then_] if [b] is true, or [else_]
      otherwise.

      WARNING: The [Typ.t]'s [read] field must be able to construct values from
      a series of field zeros.
  *)
  val if_ :
       Boolean.var
    -> typ:('var, _) Typ.t
    -> then_:'var
    -> else_:'var
    -> 'var Checked.t

  (** Add a label to all of the constraints added in the checked computation.
      If a constraint is checked and isn't satisfied, this label will be shown
      in the error message.
  *)
  val with_label : string -> 'a Checked.t -> 'a Checked.t

  (** Generate the R1CS for the checked computation. *)
  val constraint_system :
       exposing:('a Checked.t, _, 'k_var, _) Data_spec.t
    -> return_typ:('a, _) Typ.t
    -> 'k_var
    -> R1CS_constraint_system.t

  (** Internal: supplies arguments to a checked computation by storing them
      according to the {!type:Data_spec.t} and passing the R1CS versions.
  *)
  val conv :
       ('r_var -> 'r_value)
    -> ('r_var, 'r_value, 'k_var, 'k_value) Data_spec.t
    -> _ Typ.t
    -> 'k_var
    -> 'k_value

  (** Internal. Never use this.

      This applies an initial argument to a function, interpreting the argument
      within the scope of a imperative checked computation, after storing all
      of the public inputs, but only passing the arguments after computing this
      initial argument.

      It should always be possible to avoid using this; when this becomes
      unnecessary, this should be removed.
  *)
  val conv_never_use :
       (unit -> 'hack)
    -> (unit -> 'r_var, 'r_value, 'k_var, 'k_value) Data_spec.t
    -> ('hack -> 'k_var)
    -> 'k_var

  (** Generate the public input vector for a given statement. *)
  val generate_public_input :
    (_, Field.Vector.t, _, 'k_value) Data_spec.t -> 'k_value

  (** Generate a witness (auxiliary input) for the given public input.

      Returns a record of field vectors [{public_inputs; auxiliary_inputs}],
      corresponding to the given public input and generated auxiliary input.
  *)
  val generate_witness :
       ('r_var Checked.t, Proof_inputs.t, 'k_var, 'k_value) Data_spec.t
    -> return_typ:('r_var, _) Typ.t
    -> 'k_var
    -> 'k_value

  (** Generate a witness (auxiliary input) for the given public input and pass
      the result to a function.

      Returns the result of applying [f] to the record of field vectors
      [{public_inputs; auxiliary_inputs}], corresponding to the given public
      input and generated auxiliary input.
  *)
  val generate_witness_conv :
       f:(Proof_inputs.t -> 'r_value -> 'out)
    -> ('r_var Checked.t, 'out, 'k_var, 'k_value) Data_spec.t
    -> return_typ:('r_var, 'r_value) Typ.t
    -> 'k_var
    -> 'k_value

  (** Run a checked computation as the prover, without checking the
      constraints. *)
  val run_unchecked : 'a Checked.t -> 'a

  (** Run a checked computation as the prover, checking the constraints. *)
  val run_and_check : 'a As_prover.t Checked.t -> 'a Or_error.t

  (** Run a checked computation as the prover, returning [true] if the
      constraints are all satisfied, or [false] otherwise. *)
  val check : 'a Checked.t -> unit Or_error.t

  (** Run the checked computation and generate the auxiliary input, but don't
      generate a proof.

      Returns [unit]; this is for testing only.
  *)
  val generate_auxiliary_input :
       ('a Checked.t, unit, 'k_var, 'k_value) Data_spec.t
    -> return_typ:('a, _) Typ.t
    -> 'k_var
    -> 'k_value

  (** Returns the number of constraints in the constraint system.

      The optional [log] argument is called at the start and end of each
      [with_label], with the arguments [log ?start label count], where:
      - [start] is [Some true] if it the start of the [with_label], or [None]
        otherwise
      - [label] is the label added by [with_label]
      - [count] is the number of constraints at that point.
  *)
  val constraint_count :
       ?weight:(Constraint.t -> int)
    -> ?log:(?start:bool -> string -> int -> unit)
    -> _ Checked.t
    -> int

  module Test : sig
    val checked_to_unchecked :
         ('vin, 'valin) Typ.t
      -> ('vout, 'valout) Typ.t
      -> ('vin -> 'vout Checked.t)
      -> 'valin
      -> 'valout

    val test_equal :
         ?sexp_of_t:('valout -> Sexp.t)
      -> ?equal:('valout -> 'valout -> bool)
      -> ('vin, 'valin) Typ.t
      -> ('vout, 'valout) Typ.t
      -> ('vin -> 'vout Checked.t)
      -> ('valin -> 'valout)
      -> 'valin
      -> unit
  end

  val set_constraint_logger :
       (?at_label_boundary:[ `Start | `End ] * string -> Constraint.t -> unit)
    -> unit

  val clear_constraint_logger : unit -> unit
end

module type S = sig
  include Basic

  module Number :
    Number_intf.S
      with type 'a checked := 'a Checked.t
       and type field := field
       and type field_var := Field.Var.t
       and type bool_var := Boolean.var

  module Enumerable (M : sig
    type t [@@deriving enum]
  end) :
    Enumerable_intf.S
      with type 'a checked := 'a Checked.t
       and type ('a, 'b) typ := ('a, 'b) Typ.t
       and type bool_var := Boolean.var
       and type var = Field.Var.t
       and type t := M.t
end

(** The imperative interface to Snarky. *)
module type Run_basic = sig
  (** The rank-1 constraint system used by this instance. See
      {!module:Backend_intf.S.R1CS_constraint_system}. *)
  module R1CS_constraint_system : sig
    type t

    val digest : t -> Md5.t
  end

  (** Variables in the R1CS. *)
  module Var : sig
    include Comparable.S

    val create : int -> t

    val index : t -> int
  end

  (** The finite field over which the R1CS operates. *)
  type field

  module Bigint : sig
    include Snarky_intf.Bigint_intf.Extended with type field := field

    val of_bignum_bigint : Bignum_bigint.t -> t

    val to_bignum_bigint : t -> Bignum_bigint.t
  end

  (** Rank-1 constraints over {!type:Field.t}s. *)
  module rec Constraint : sig
    type t = (Field.t, Field.Constant.t) Constraint0.t

    type 'k with_constraint_args = ?label:string -> 'k

    val boolean : (Field.t -> t) with_constraint_args

    val equal : (Field.t -> Field.t -> t) with_constraint_args

    val r1cs : (Field.t -> Field.t -> Field.t -> t) with_constraint_args

    val square : (Field.t -> Field.t -> t) with_constraint_args
  end

  (** The data specification for checked computations. *)
  and Data_spec : sig
    (** A list of {!type:Typ.t} values, describing the inputs to a checked
        computation. The type [('r_var, 'r_value, 'k_var, 'k_value) t]
        represents
        - ['k_value] is the OCaml type of the computation
        - ['r_value] is the OCaml type of the result
        - ['k_var] is the type of the computation within the R1CS
        - ['k_value] is the type of the result within the R1CS.

        This functions the same as OCaml's default list type:
{[
  Data_spec.[typ1; typ2; typ3]

  Data_spec.(typ1 :: typs)

  let open Data_spec in
  [typ1; typ2; typ3; typ4; typ5]

  let open Data_spec in
  typ1 :: typ2 :: typs

]}
        all function as you would expect.
    *)
    type ('r_var, 'r_value, 'k_var, 'k_value) t =
      ('r_var, 'r_value, 'k_var, 'k_value, field) Typ0.Data_spec.t

    (** [size [typ1; ...; typn]] returns the number of {!type:Var.t} variables
        allocated by allocating [typ1], followed by [typ2], etc. *)
    val size : (_, _, _, _) t -> int

    include module type of Typ0.Data_spec0
  end

  (** Mappings from OCaml types to R1CS variables and constraints. *)
  and Typ : sig
    type ('var, 'value) t =
      ('var, 'value, field, (unit, field) Checked.t) Types.Typ.t

    (** Basic instances: *)

    val unit : (unit, unit) t

    val field : (Field.t, field) t

    (** Common constructors: *)

    val tuple2 :
         ('var1, 'value1) t
      -> ('var2, 'value2) t
      -> ('var1 * 'var2, 'value1 * 'value2) t

    (** synonym for tuple2 *)
    val ( * ) :
         ('var1, 'value1) t
      -> ('var2, 'value2) t
      -> ('var1 * 'var2, 'value1 * 'value2) t

    val tuple3 :
         ('var1, 'value1) t
      -> ('var2, 'value2) t
      -> ('var3, 'value3) t
      -> ('var1 * 'var2 * 'var3, 'value1 * 'value2 * 'value3) t

    val list : length:int -> ('var, 'value) t -> ('var list, 'value list) t

    val array : length:int -> ('var, 'value) t -> ('var array, 'value array) t

    (** Unpack a {!type:Data_spec.t} list to a {!type:t}. The return value relates
        a polymorphic list of OCaml types to a polymorphic list of R1CS types. *)
    val hlist :
         (unit, unit, 'k_var, 'k_value) Data_spec.t
      -> ((unit, 'k_var) H_list.t, (unit, 'k_value) H_list.t) t

    (** Convert relationships over
        {{:https://en.wikipedia.org/wiki/Isomorphism}isomorphic} types: *)

    val transport :
         ('var, 'value1) t
      -> there:('value2 -> 'value1)
      -> back:('value1 -> 'value2)
      -> ('var, 'value2) t

    val transport_var :
         ('var1, 'value) t
      -> there:('var2 -> 'var1)
      -> back:('var1 -> 'var2)
      -> ('var2, 'value) t

    val of_hlistable :
         (unit, unit, 'k_var, 'k_value) Data_spec.t
      -> var_to_hlist:('var -> (unit, 'k_var) H_list.t)
      -> var_of_hlist:((unit, 'k_var) H_list.t -> 'var)
      -> value_to_hlist:('value -> (unit, 'k_value) H_list.t)
      -> value_of_hlist:((unit, 'k_value) H_list.t -> 'value)
      -> ('var, 'value) t

    (** [Typ.t]s that make it easier to write a [Typ.t] for a mix of R1CS data
        and normal OCaml data.

        Using this module is strongly discouraged.
    *)
    module Internal : sig
      (** A do-nothing [Typ.t] that returns the input value for all modes.

          This is the dual of [ref], which allows [OCaml] values from
          [As_prover] blocks to pass through the [Checked] world.

          Note: Reading or writing using this [Typ.t] will assert that the
          argument and the value stored are physically equal -- ie. that they
          refer to the same object.
      *)
      val snarkless : 'a -> ('a, 'a) t

      (** A [Typ.t] for marshalling OCaml values generated in [As_prover]
          blocks, while keeping them opaque to the [Checked] world.

          This is the dual of [snarkless], which allows [OCaml] values from the
          [Checked] world to pass through [As_prover] blocks.
      *)
      val ref : unit -> ('a As_prover.Ref.t, 'a) t
    end

    module type S =
      Typ0.Intf.S
        with type field := Field.Constant.t
         and type field_var := Field.t
         and type _ checked = unit

    val mk_typ :
         (module S with type Var.t = 'var and type Value.t = 'value)
      -> ('var, 'value) t
  end

  (** Representation of booleans within a field.

      This representation ties the value of [true] to {!val:Field.one} and
      [false] to {!val:Field.zero}, adding a check in {!val:Boolean.typ} to
      ensure that these are the only vales. *)
  and Boolean : sig
    type var = Field.t Boolean0.t

    type value = bool

    val true_ : var

    val false_ : var

    val if_ : var -> then_:var -> else_:var -> var

    val not : var -> var

    val ( && ) : var -> var -> var

    val ( &&& ) : var -> var -> var

    val ( || ) : var -> var -> var

    val ( ||| ) : var -> var -> var

    val ( lxor ) : var -> var -> var

    val any : var list -> var

    val all : var list -> var

    (** Convert a value in a field to a boolean, adding checks to the R1CS that
       it is a valid boolean value. *)
    val of_field : Field.t -> var

    val var_of_value : value -> var

    (** The relationship between {!val:var} and {!val:value}, with a check that
        the value is valid (ie. {!val:Field.zero} or {!val:Field.one}). *)
    val typ : (var, value) Typ.t

    (** {!val:typ} without a validity check for the underlying field value. *)
    val typ_unchecked : (var, value) Typ.t

    val equal : var -> var -> var

    module Expr : sig
      (** Expression trees. *)
      type t

      val ( ! ) : var -> t

      val ( && ) : t -> t -> t

      val ( &&& ) : t -> t -> t

      val ( || ) : t -> t -> t

      val ( ||| ) : t -> t -> t

      val any : t list -> t

      val all : t list -> t

      val not : t -> t

      (** Evaluate the expression tree. *)
      val eval : t -> var

      val assert_ : t -> unit
    end

    module Unsafe : sig
      val of_cvar : Field.t -> var
    end

    module Assert : sig
      val ( = ) : var -> var -> unit

      val is_true : var -> unit

      val any : var list -> unit

      val all : var list -> unit

      val exactly_one : var list -> unit
    end

    module Array : sig
      val any : var array -> var

      val all : var array -> var

      module Assert : sig
        val any : var array -> unit

        val all : var array -> unit
      end
    end
  end

  and Field : sig
    module Constant : sig
      (** The finite field over which the R1CS operates. *)
      type t = field [@@deriving bin_io, sexp, hash, compare]

      (** A generator for Quickcheck tests. *)
      val gen : t Core_kernel.Quickcheck.Generator.t

      (** A uniform generator for Quickcheck tests. *)
      val gen_uniform : t Core_kernel.Quickcheck.Generator.t

      include Snarky_intf.Field.Extended with type t := t

      include Stringable.S with type t := t

      (** Convert a field element into its constituent bits. *)
      val unpack : t -> bool list

      (** Convert a list of bits into a field element. *)
      val project : bool list -> t

      (** Get the least significant bit of a field element. *)
      val parity : t -> bool
    end

    type t = field Cvar.t

    val size_in_bits : int

    val size : Bignum_bigint.t

    (** For debug purposes *)
    val length : t -> int

    val var_indices : t -> int list

    (** Convert a {!type:t} value to its constituent constant and a list of
          scaled R1CS variables. *)
    val to_constant_and_terms : t -> field option * (field * Var.t) list

    val constant : field -> t

    val to_constant : t -> field option

    val linear_combination : (field * t) list -> t

    val sum : t list -> t

    val add : t -> t -> t

    val negate : t -> t

    val sub : t -> t -> t

    val scale : t -> field -> t

    val project : Boolean.var list -> t

    val pack : Boolean.var list -> t

    val of_int : int -> t

    val one : t

    val zero : t

    val mul : t -> t -> t

    val square : t -> t

    val div : t -> t -> t

    val inv : t -> t

    val is_square : t -> Boolean.var

    val sqrt : t -> t

    val sqrt_check : t -> t * Boolean.var

    val equal : t -> t -> Boolean.var

    val unpack : t -> length:int -> Boolean.var list

    val unpack_flagged :
      t -> length:int -> Boolean.var list * [ `Success of Boolean.var ]

    val unpack_full : t -> Boolean.var Bitstring_lib.Bitstring.Lsb_first.t

    val parity : ?length:int -> t -> Boolean.var

    val choose_preimage_var : t -> length:int -> Boolean.var list

    type comparison_result = { less : Boolean.var; less_or_equal : Boolean.var }

    val compare : bit_length:int -> t -> t -> comparison_result

    val if_ : Boolean.var -> then_:t -> else_:t -> t

    val ( + ) : t -> t -> t

    val ( - ) : t -> t -> t

    val ( * ) : t -> t -> t

    val ( / ) : t -> t -> t

    module Unsafe : sig
      val of_index : int -> t
    end

    module Assert : sig
      val lte : bit_length:int -> t -> t -> unit

      val gte : bit_length:int -> t -> t -> unit

      val lt : bit_length:int -> t -> t -> unit

      val gt : bit_length:int -> t -> t -> unit

      val not_equal : t -> t -> unit

      val equal : t -> t -> unit

      val non_zero : t -> unit
    end

    val typ : (t, Constant.t) Typ.t
  end

  (** The functions in this module may only be run as the prover; trying to
      run them outside of functions that refer to [As_prover.t] will result in
      a runtime error. *)
  and As_prover : sig
    (** This type marks function arguments that can include function calls from
        this module. Using these functions outside of these will result in a
        runtime error. *)
    type 'a t = 'a

    type 'a as_prover = 'a t

    (** Opaque references for use by the prover in a checked computation. *)
    module Ref : sig
      (** A mutable reference to an ['a] value, which may be used in checked
          computations. *)
      type 'a t

      val create : (unit -> 'a) as_prover -> 'a t

      val get : 'a t -> 'a as_prover

      val set : 'a t -> 'a -> unit as_prover
    end

    val in_prover_block : unit -> bool

    val read_var : Field.t -> Field.Constant.t

    val read : ('var, 'value) Typ.t -> 'var -> 'value

    include Snarky_intf.Field.Extended with type t := field

    (** Convert a field element into its constituent bits. *)
    val unpack : field -> bool list

    val project : bool list -> field
  end

  and Proof_inputs : sig
    type t =
      { public_inputs : Field.Constant.Vector.t
      ; auxiliary_inputs : Field.Constant.Vector.t
      }
  end

  module Bitstring_checked : sig
    type t = Boolean.var list

    val equal : t -> t -> Boolean.var

    (** Equivalent to [equal], but avoids computing field elements to represent
        chunks of the list when not necessary.

        NOTE: This will do extra (wasted) work before falling back to the
              behaviour of [equal] when the values are not equal.
    *)
    val equal_expect_true : t -> t -> Boolean.var

    val lt_value :
         Boolean.var Bitstring_lib.Bitstring.Msb_first.t
      -> bool Bitstring_lib.Bitstring.Msb_first.t
      -> Boolean.var

    module Assert : sig
      val equal : t -> t -> unit
    end
  end

  module Handle : sig
    type ('var, 'value) t

    val value : (_, 'value) t -> (unit -> 'value) As_prover.t

    val var : ('var, _) t -> 'var
  end

  type response = Request.response

  val unhandled : response

  type request = Request.request =
    | With :
        { request : 'a Request.t; respond : 'a Request.Response.t -> response }
        -> request

  module Handler : sig
    type t = request -> response
  end

  val assert_ : ?label:string -> Constraint.t -> unit

  val assert_all : ?label:string -> Constraint.t list -> unit

  val assert_r1cs : ?label:string -> Field.t -> Field.t -> Field.t -> unit

  val assert_square : ?label:string -> Field.t -> Field.t -> unit

  val as_prover : (unit -> unit) As_prover.t -> unit

  val next_auxiliary : unit -> int

  val request_witness :
    ('var, 'value) Typ.t -> (unit -> 'value Request.t) As_prover.t -> 'var

  val perform : (unit -> unit Request.t) As_prover.t -> unit

  (** TODO: Come up with a better name for this in relation to the above *)
  val request :
       ?such_that:('var -> unit)
    -> ('var, 'value) Typ.t
    -> 'value Request.t
    -> 'var

  val exists :
       ?request:(unit -> 'value Request.t) As_prover.t
    -> ?compute:(unit -> 'value) As_prover.t
    -> ('var, 'value) Typ.t
    -> 'var

  val exists_handle :
       ?request:(unit -> 'value Request.t) As_prover.t
    -> ?compute:(unit -> 'value) As_prover.t
    -> ('var, 'value) Typ.t
    -> ('var, 'value) Handle.t

  val handle : (unit -> 'a) -> Handler.t -> 'a

  val handle_as_prover : (unit -> 'a) -> (unit -> Handler.t As_prover.t) -> 'a

  (** [if_ b ~then_ ~else_] returns [then_] if [b] is true, or [else_]
      otherwise.

      WARNING: The [Typ.t]'s [read] field must be able to construct values from
      a series of field zeros.
  *)
  val if_ :
    Boolean.var -> typ:('var, _) Typ.t -> then_:'var -> else_:'var -> 'var

  val with_label : string -> (unit -> 'a) -> 'a

  val make_checked : (unit -> 'a) -> ('a, field) Types.Checked.t

  val constraint_system :
       exposing:(unit -> 'a, _, 'k_var, _) Data_spec.t
    -> return_typ:('a, _) Typ.t
    -> 'k_var
    -> R1CS_constraint_system.t

  val generate_witness :
       (unit -> 'a, Proof_inputs.t, 'k_var, 'k_value) Data_spec.t
    -> return_typ:('a, _) Typ.t
    -> 'k_var
    -> 'k_value

  (** Generate the public input vector for a given statement. *)
  val generate_public_input :
    (_, Field.Constant.Vector.t, _, 'k_value) Data_spec.t -> 'k_value

  val generate_witness_conv :
       f:(Proof_inputs.t -> 'r_value -> 'out)
    -> (unit -> 'r_var, 'out, 'k_var, 'k_value) Data_spec.t
    -> return_typ:('r_var, 'r_value) Typ.t
    -> 'k_var
    -> 'k_value

  val run_unchecked : (unit -> 'a) -> 'a

  val run_and_check : (unit -> (unit -> 'a) As_prover.t) -> 'a Or_error.t

  module Run_and_check_deferred (M : sig
    type _ t

    val return : 'a -> 'a t

    val map : 'a t -> f:('a -> 'b) -> 'b t
  end) : sig
    val run_and_check :
      (unit -> (unit -> 'a) As_prover.t M.t) -> 'a Or_error.t M.t
  end

  val check : (unit -> 'a) -> unit Or_error.t

  val constraint_count :
       ?weight:(Constraint.t -> int)
    -> ?log:(?start:bool -> string -> int -> unit)
    -> (unit -> 'a)
    -> int

  val set_constraint_logger :
       (?at_label_boundary:[ `Start | `End ] * string -> Constraint.t -> unit)
    -> unit

  val clear_constraint_logger : unit -> unit

  val in_prover : unit -> bool

  val in_checked_computation : unit -> bool

  module Internal_Basic :
    Basic
      with type field = field
       and type 'a As_prover.Ref.t = 'a As_prover.Ref.t

  val run_checked : 'a Internal_Basic.Checked.t -> 'a
end

module type Run = sig
  include Run_basic

  module Number :
    Number_intf.Run
      with type field := field
       and type field_var := Field.t
       and type bool_var := Boolean.var

  module Enumerable (M : sig
    type t [@@deriving enum]
  end) :
    Enumerable_intf.Run
      with type ('a, 'b) typ := ('a, 'b) Typ.t
       and type bool_var := Boolean.var
       and type var = Field.t
       and type t := M.t
end
