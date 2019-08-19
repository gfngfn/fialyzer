open Base
open Fialyzer
open Type
open Solver

let sexp_of_solution sol =
  Map.map ~f:pp sol
  |> [%sexp_of: string Map.M(Type_variable).t]

let eq (ty1, ty2) =
  let link = Ast.Ref (-1, Var "__dummy_expr__") in
  Constraint.Eq {lhs=ty1; rhs=ty2; link}

let subtype (ty1, ty2) =
  let link = Ast.Ref (-1, Var "__dummy_expr__") in
  Constraint.Subtype {lhs=ty1; rhs=ty2; link}

let filename = "__unit_test_filename__"

let%expect_test "solver" =
  let print c =
    solve ~filename init c
    |> Result.map ~f:sexp_of_solution
    |> [%sexp_of: (Sexp.t, exn) Result.t]
    |> Expect_test_helpers_kernel.print_s in

  let create_vars n =
    Type_variable.reset_count ();
    List.init n ~f:(fun _ -> Type_variable.create ()) |> List.rev in

  print Empty;
  [%expect {| (Ok ()) |}];

  let [a] = create_vars 1 in
  print (eq (Type.of_elem (TyVar a), Type.of_elem TyNumber));
  [%expect {| (Ok ((a "number()"))) |}];

  let [a] = create_vars 1 in
  print (subtype (Type.of_elem (TyVar a), Type.of_elem TyNumber));
  [%expect {| (Ok ((a "number()"))) |}];

  let [a; b] = create_vars 2 in
  print (subtype
           (Type.of_elem (TyTuple [Type.of_elem (TyVar a); Type.of_elem (TyVar b)]),
            Type.of_elem (TyTuple [Type.of_elem TyNumber; Type.of_elem TyAtom])));
  [%expect {|
    (Ok (
      (a "number()")
      (b "atom()"))) |}];
(*
  let [a; b] = create_vars 2 in
  print (subtype (TyUnion [TyVar a; TyVar b], TyNumber));
  [%expect {|
    (Ok (
      (a TyNumber)
      (b TyNumber))) |}];
 *)
  print (subtype (TyBottom, TyAny));
  [%expect {| (Ok ()) |}];

  print (subtype (TyAny, TyAny));
  [%expect {| (Ok ()) |}];

  print (subtype (TyBottom, TyAny));
  [%expect {| (Ok ()) |}];

  print (subtype (TyBottom, TyBottom));
  [%expect {| (Ok ()) |}];

  print (subtype (Type.of_elem TyNumber, Type.of_elem TyAtom));
  [%expect {|
    (Error (
      lib/known_error.ml.FialyzerError (
        TypeError ((
          (filename __unit_test_filename__)
          (line     -1)
          (actual   (TyUnion (TyNumber)))
          (expected (TyUnion (TyAtom)))
          (message "there is no solution that satisfies subtype constraints")))))) |}];

  (*
   * [N : a] |- case N of 0 -> 'foo'; 'ok' -> 123 end
   *)
  let [a; b] = create_vars 2 in
  print (Disj [
             Conj [eq (Type.of_elem (TyVar b), Type.of_elem (TySingleton (Atom "foo")));
                   eq (Type.of_elem (TyVar a), Type.of_elem (TySingleton (Number (Int 0))))];
             Conj [eq (Type.of_elem (TyVar b), Type.of_elem (TySingleton (Number (Int 123))));
                   eq (Type.of_elem (TyVar a), Type.of_elem (TySingleton (Atom "ok")))];
        ]);
  [%expect {|
            (Ok (
              (a "0 | 'ok'")
              (b "'foo' | 123")))
            |}];

  (*
   * `solve_disj {X |-> number()} [(X <: 1); (X <: 2)]` should be `{X |-> 1 | 2}`.
   * see: https://github.com/dwango/fialyzer/issues/176
   *)
  let [a] = create_vars 1 in
  print (Conj [
             subtype (Type.of_elem (TyVar a), Type.of_elem TyNumber);
             Disj [
                 subtype (Type.of_elem (TyVar a), Type.of_elem (TySingleton (Number (Int 1))));
                 subtype (Type.of_elem (TyVar a), Type.of_elem (TySingleton (Number (Int 2))));
               ]
           ]);
  [%expect {| (Ok ((a "1 | 2"))) |}];

  let [a; b] = create_vars 2 in
  print (Conj [
             subtype (Type.of_elem (TyVar a), Type.of_elem TyNumber);
             Disj [
                 subtype (Type.of_elem (TyVar a), Type.of_elem (TySingleton (Number (Int 1))));
                 subtype (Type.of_elem (TyVar a), Type.of_elem (TySingleton (Number (Int 2))));
             ];
             subtype (Type.of_elem (TyVar b), Type.of_elem (TyList (Type.of_elem (TyVar a))));
           ]);
  [%expect {|
    (Ok (
      (a "1 | 2")
      (b "[1 | 2]"))) |}];

  let [a] = create_vars 1 in
  print (Disj [
    subtype (Type.of_elem (TyVar a), Type.of_elem (TyList TyBottom));
    subtype (Type.of_elem (TyVar a), Type.of_elem (TyList (Type.of_elem TyAtom)))
  ]);
  [%expect {| (Ok ((a "[atom()]"))) |}];

  let [a] = create_vars 1 in
  print (Conj [
    eq (Type.of_elem (TyList TyBottom), Type.of_elem (TyList (Type.of_elem (TyVar a))))
  ]);
  [%expect {|
    (Ok ((a "none()"))) |}];


  ()
