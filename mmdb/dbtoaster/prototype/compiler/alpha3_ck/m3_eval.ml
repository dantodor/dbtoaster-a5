(* open M3;; *)


(* General map types and helper functions *)

module StringMap = Map.Make (String);;
(* the keys are variable or map names *)

module ListMap = Map.Make (struct
   type t = const_t list
   let compare = compare
end);;

type slice_t = int ListMap.t;;
type map_t = slice_t ListMap.t;;
type db_t = map_t StringMap.t;;



(* if there are duplicate keys, they get overwritten *)
let list_to_lmap l =
   List.fold_left (fun m (k,v) ->   ListMap.add k v m)   ListMap.empty l;;


let list_to_lmap2 l =
   List.fold_left (fun m (k,v) ->
                   let v2 = if(ListMap.mem k m) then ListMap.find k m
                            else 0 in
                   ListMap.add k (v+v2) m)
                  ListMap.empty l
;;

let list_to_smap l =
   List.fold_left (fun m (k,v) -> StringMap.add k v m) StringMap.empty l;;

let map_to_list fold_f f m = fold_f (fun s n l -> (s, f n) :: l) m [];;

let showslice m = map_to_list ListMap.fold   (fun x->x) m;;
let lshowmap  m = map_to_list ListMap.fold   showslice  m;;
let gshowmap  m = map_to_list StringMap.fold lshowmap   m;;
let sshowmap  m = map_to_list StringMap.fold (fun x->x) m;;

let list_to_string elem_to_string l =
   "["^(List.fold_left (fun s x -> s^" "^(elem_to_string x)) "" l)^" ]";;

let slice_to_string m = list_to_string
   (fun (k,v) -> "("^(list_to_string string_of_int k)^", "
                    ^(string_of_int v)^")")
   (showslice m);;


let map_product valcomb_f m1 m2 =
   let l1 = (showslice m1) in
   let l2 = (showslice m2) in
   let aux (k1, v1) = List.map (fun (k2, v2) -> ((k1 @ k2),
                                                 (valcomb_f v1 v2))) l2
   in
   list_to_lmap (List.flatten (List.map aux l1))
;;

let merge reconcile_f (m1: 'a) (m2: 'a): 'a =
   ListMap.fold (fun k v m -> ListMap.add k
      (if (ListMap.mem k m) then
         (reconcile_f (ListMap.find k m) v)
       else v) m) m1 m2;;

let slice_merge sl1 sl2 : slice_t = merge (+) sl1 sl2;;



(* VARIABLE VALUATIONS *)
module Valuation =
struct
   type t = int StringMap.t

   let make (vars: var_t list) (values: const_t list) : t =
      list_to_smap (List.combine vars values)

   (* assume that theta 1 and 2 agree on the keys they have in common *)
   let combine (theta1:t) (theta2:t) : t =
      StringMap.fold (fun k v t -> StringMap.add k v t) theta1 theta2

   let to_list (theta:t) = map_to_list StringMap.fold (fun x->x) theta

   let consistent (theta1: t) (theta2: t) : bool =
      List.for_all (fun (x,y) -> (not(StringMap.mem x theta2)) ||
                                    ((StringMap.find x theta2) = y))
                   (map_to_list StringMap.fold (fun x->x) theta1)

   let apply (theta:t) l = List.map (fun x -> StringMap.find x theta) l

   let dom (theta:t) = let (dom, rng) = List.split (to_list theta) in dom
end;;



(* THE INTERPRETER *)


let rec eval_calc (incr_calc: calc_t)
                  (theta: Valuation.t) (db: db_t)
                : (var_t list * slice_t * db_t) =
(*
   print_string("CALC <incr> "^(list_to_string
        (fun (k,v) -> "("^k^", "^(string_of_int v)^")") (sshowmap theta))
        ^" <db> --   ");
*)
   (* do arithmetics *)
   let do_op op m1 m2 =
      let (outv1, res1, db1) = eval_calc m1 theta db in
      let (outv2, res2, db2) = eval_calc m2 theta db1 in
         ((outv1@outv2), (map_product op res1 res2), db2)
         (* the variable ordering is not necessarily the same as in
            the map outv spec. *)
   in
   (* check a condition *)
   let tst (op: int -> int -> bool) m1 m2 m =
       let int_op x y = if (op x y) then 1 else 0 in
       let (cond_outv, bb, db1) = do_op int_op m1 m2 in
       if (List.for_all (fun (_,v) -> (v=1)) (showslice bb)) then
          (eval_calc m theta db1)
       else ([], (list_to_lmap [([], 0)]), db1)
            (* TODO: is it correct to assume there are no variables here *)
   in
   match incr_calc with
      MapAccess(mapn, inv, outv, init_calc) ->
      (
         let m        : map_t        = (StringMap.find mapn db) in
         let inv_imgs : const_t list = apply theta inv
         in
         if (ListMap.mem inv_imgs m) then
             (outv, (ListMap.find inv_imgs m), db)
          else
             (* initial value computation for leaves of the expression tree. *)
             let (init_outv, init_slice, db1) = eval_calc init_calc theta db in
             (init_outv, init_slice,
              StringMap.add mapn (ListMap.add inv_imgs init_slice m) db1)
      )
    | Add (c1, c2)                -> do_op ( + ) c1 c2
    | Mult(c1, c2)                -> do_op ( * ) c1 c2
    | IfThenElse0( Lt(c1, c2), c) -> tst  ( <  ) c1 c2 c
    | IfThenElse0(Leq(c1, c2), c) -> tst  ( <= ) c1 c2 c
    | IfThenElse0( Eq(c1, c2), c) -> tst  ( =  ) c1 c2 c
    | Const(i)                    -> ([], list_to_lmap [([], i)], db)
    | Var(x) -> let v = StringMap.find x theta in
                ([x], list_to_lmap [([v], v)], db)
                (* note: x is not necessarily an out-var! remove from the
                   slice keys later! *)
    | Null(outv) -> (outv, (list_to_lmap []), db)
;;



(* postprocess the results of eval_calc.
   extends the keys of slice back to the signature of the lhs map *)
let eval_calc2 lhs_outv (calc: calc_t) (theta: Valuation.t) (db: db_t)
                : (slice_t * db_t) =
   let ((rhs_outv: var_t list), slice0, db0) = (eval_calc calc theta db)
   in
   let slice_filter (k,_) =
      (Valuation.consistent theta (Valuation.make rhs_outv k))
   in
   let key_refiner (k,v) =  (* valuations are consistent *)
      let ext_theta = Valuation.combine theta (Valuation.make rhs_outv k) in
                  (* normalizes the key orderings to that of the variable
                     ordering lhs_outv. *)
      let new_k = Valuation.apply ext_theta lhs_outv in
      (new_k, v)
   in
   let slice_list = (List.map key_refiner
                       (List.filter slice_filter (showslice slice0)))
   in
      (* in the presence of bigsum variables, there may be duplicates
         after key_refinement. These have to be summed up. *)
   ((list_to_lmap2 slice_list), db0)
;;


let eval_stmt (theta: Valuation.t) (db: db_t)
              ((lhs_mapn, lhs_inv, lhs_outv, init_calc), incr_calc) : db_t =
(*
   print_string("STMT "^(list_to_string
        (fun (k,v) -> "("^k^", "^(string_of_int v)^")") (sshowmap theta))
        ^" <db> (("^lhs_mapn^" <lhs_inv> <lhs_outv> <init_calc>), incr_calc) --   ");
*)
   let lhs_inv_imgs     = Valuation.apply theta lhs_inv in
   let lhs_map:map_t    = (StringMap.find lhs_mapn db) in
   let (old_slice, db1) =
      if (ListMap.mem lhs_inv_imgs lhs_map) then
         ((ListMap.find lhs_inv_imgs lhs_map), db)
      else
         (* initial value computation. This is the case where information
            is arriving bottom-up in out-vars; possibly some these valuations
            are new. *)
         eval_calc2 lhs_outv init_calc theta db
   in
   let (delta, db2) = eval_calc2 lhs_outv incr_calc theta db1 in
   let new_slice    = slice_merge old_slice delta in
   let m = ListMap.add lhs_inv_imgs new_slice lhs_map (* overwrite *) in
   StringMap.add lhs_mapn m db2
;;




let eval_stmt_loop (theta: Valuation.t) (db: db_t)
                   ((lhs_mapn, lhs_inv, lhs_outv, init_calc), incr_calc)
                   : db_t =
(*
   print_string("STMT-LOOP "^(list_to_string
        (fun (k,v) -> "("^k^", "^(string_of_int v)^")") (sshowmap theta))
        ^" <db> (("^lhs_mapn^", "^(list_to_string (fun x->x) lhs_inv)
        ^", "^(list_to_string (fun x->x) lhs_outv)^", <init>), <incr>) --   ");
*)
   let (inv_imgs, _) = List.split
      (map_to_list ListMap.fold (fun x->x) (StringMap.find lhs_mapn db))
   in
   let ii_filter db inv_img : db_t =
      let inv_theta  = (Valuation.make lhs_inv inv_img) in
      if (Valuation.consistent theta inv_theta) then
        (eval_stmt (Valuation.combine theta inv_theta) db
                ((lhs_mapn, lhs_inv, lhs_outv, init_calc), incr_calc))
      else db
   in
   List.fold_left ii_filter db inv_imgs
;;


let eval_trig (trig_args: var_t list) (tuple: const_t list) db block =
   let theta = Valuation.make trig_args tuple
   in
   List.fold_left (fun db stmt -> eval_stmt_loop theta db stmt) db block;;



let make_empty_db schema: db_t =
   list_to_smap (List.map (fun (mapn, itypes, rtypes) ->
             (mapn, (if(List.length itypes = 0) then
                list_to_lmap [([], list_to_lmap [])]
             else list_to_lmap []))
            ) schema)
;;



