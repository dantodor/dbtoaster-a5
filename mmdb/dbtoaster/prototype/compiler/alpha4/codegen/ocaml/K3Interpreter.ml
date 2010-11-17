open Util
open M3
open K3.SR
open Values
open Database
open Sources
open Sources.Adaptors


module K3CG : K3Codegen.CGI
    with type db_t = NamedK3Database.db_t and
         type value_t = K3Value.t
=
struct

    open K3Value
    type value_t = K3Value.t

    module Env = K3Valuation
    
    module MC  = K3ValuationMap
    module DB  = NamedK3Database

    (* Use runtime for main method *)
    module RT  = Runtime.Make(DB)
    open RT

    type slice_env_t = (string * value_t) list
    
    type env_t       = Env.t * slice_env_t 
    type db_t        = DB.db_t

    type eval_t      = env_t -> db_t -> value_t
    type code_t      =
          Eval of eval_t
        | Trigger of M3.pm_t * M3.rel_id_t * (const_t list -> db_t -> unit)
        | Main of (unit -> unit) 

    type op_t        = value_t -> value_t -> value_t

    (* Slice environment *)
    let is_env_value v (_,th) = List.mem_assoc v th
    let get_env_value v (_,th) = List.assoc v th

    (* Helpers *)
    let get_expr expr_opt = match expr_opt with
        | None -> ""
        | Some(e) -> " at code: "^(string_of_expr e)

    let get_eval e = match e with
        | Eval(e) -> e
        | _ -> failwith "unable to eval expr"

    let get_trigger e = match e with
        | Trigger(x,y,z) -> (x,y,z)
        | _ -> failwith "unable to eval trigger"

    let rec is_flat t = match t with
        | TFloat | TInt -> true
        | TTuple t -> List.for_all is_flat t
        | _ -> false

    let value_of_float x = Float(x)
    let value_of_const_t x = match x with CFloat(y) -> Float(y)
    
    let float_of_value x = match x with
        | Float f -> f | Int i -> float_of_int i
        | _ -> failwith ("invalid float: "^(string_of_value x))

    let float_of_const_t x = match x with CFloat(f) -> f 

    let const_t_of_value x = match x with
        | Float f -> CFloat f | Int i -> CFloat (float_of_int i)
        | _ -> failwith ("invalid const_t: "^(string_of_value x))

    let const_t_of_float x = CFloat(x)

    let value_of_tuple x = Tuple(x)
    let tuple_of_value x = match x with
        | Tuple(y) -> y
        | _ -> failwith ("invalid tuple: "^(string_of_value x))

    let pop_back l =
        let x,y = List.fold_left
            (fun (acc,rem) v -> match rem with 
                | [] -> (acc, [v]) | _ -> (acc@[v], List.tl rem)) 
            ([], List.tl l) l
        in x, List.hd y

    let tuple_of_kv (k,v) = Tuple(k@[v])

    let kv_of_tuple t = match t with
        | Tuple(t_v) -> pop_back t_v 
        | _ -> failwith ("invalid tuple: "^(string_of_value t))

    (* Map/aggregate tuple+multivariate function evaluation helpers.
     * uses fields of a tuple to evaluate a multivariate function if the
     * function is a schema application.
     *)

    (* Nested, multivariate function application *)
    let rec apply_list fv l =
        match fv,l with
        | (Fun _, []) -> fv
        | (v, []) -> v
        | (Fun f, h::t) -> apply_list (f h) t
        | (_,_) -> failwith "invalid schema application"
    
    let apply_fn_list th db l = List.map (fun f -> (get_eval f) th db) l

    (* Persistent collection converters to temporary values *)
    let smc_to_tlc m = MC.fold (fun k v acc ->
        let t_v = k@[v] in (value_of_tuple t_v)::acc) [] m
        
    let dmc_to_smlc m = MC.fold (fun k v acc -> (k, v)::acc) [] m

    let dmc_to_c m = MC.fold(fun k m1 acc ->
        let v = TupleList(smc_to_tlc m1) in (Tuple(k@[v]))::acc) [] m

    let smlc_to_c smlc = List.map (fun (k,m) ->
        Tuple(k@[TupleList(smc_to_tlc m)])) smlc 

    let nmc_to_c nm = smc_to_tlc nm

    let match_key_prefix prefix k =
        try fst (List.fold_left (fun (run,rem) v -> match run, rem with
            | (true,[]) -> (run, rem) (* could terminate early on success *)
            | (false, _) -> raise Not_found (* early termination for failure *)
            | (_,_) -> (run && (List.hd rem) = v, List.tl rem))
            (true,prefix) k)
        with Not_found -> false

    let tuple_fields t_v idx = snd (List.fold_left (fun (cur,acc) v ->
        (cur+1, if List.mem cur idx then acc@[v] else acc)) (0,[]) t_v)


    (* Operators *)
    let promote_op f_op i_op x y =
        match x,y with
        | (Float f, Int i) -> Float(f_op f (float_of_int i))
        | (Int i, Float f) -> Float(f_op (float_of_int i) f)
        | (Float f1, Float f2) -> Float(f_op f1 f2)
        | (Int i1, Int i2) -> Int(i_op i1 i2)
        | (_,_) -> failwith "invalid arithmetic operands" 
    
    (* Comparisons:
     * -- supports base types, tuples and lists. Tuple and list comparison
     *    works as with standard OCaml semantics (structural comparisons) *)
    (* TODO:
     * -- collection comparisons have list semantics here, e.g. element order
     * matters. Generalize to support set/bag semantics as needed. *)
    let int_op (op : 'a -> 'a -> bool) x y =
        match (x,y) with
        | Unit,_ | _,Unit -> failwith "invalid comparison to unit"
        | _,_ -> if op x y then Int(1) else Int(0) 
    
    let add_op  = promote_op (+.) (+)
    let mult_op = promote_op ( *. ) ( * )
    let lt_op   = (int_op (< ))
    let leq_op  = (int_op (<=))
    let eq_op   = (int_op (= ))
    let neq_op  = (int_op (<>))
    
    let ifthenelse0_op cond v = 
        let aux v = match v with
            | Int _ -> Int(0) | Float _ -> Float(0.0)
            | _ -> failwith "invalid then clause value"
        in match cond with
        | Float(bcond) -> if bcond <> 0.0 then v else aux v
        | Int(bcond) -> if bcond <> 0 then v else aux v
        | _ -> failwith "invalid predicate value"


    (* Terminals *)
    let const ?(expr = None) k = Eval(fun th db -> value_of_const_t k)
    let var ?(expr = None) v _ = Eval(fun th db -> 
        if (Env.bound v (fst th)) then Env.value v (fst th)
        else if is_env_value v th then get_env_value v th 
        else failwith ("Var("^v^"): theta="^(Env.to_string (fst th))))

    (* Tuples *)
    let tuple ?(expr = None) field_l = Eval(fun th db ->
        Tuple(apply_fn_list th db field_l))

    let project ?(expr = None) tuple idx = Eval(fun th db ->
        match (get_eval tuple) th db with
        | Tuple(t_v) -> Tuple(tuple_fields t_v idx)
        | _ -> failwith ("invalid tuple for projection"^(get_expr expr)))

    (* Native collections *)
    
    let singleton ?(expr = None) el el_t =
        let rv_f v = match el_t with
            | TTuple t ->
                if List.for_all is_flat t then TupleList([v])
                else ListCollection([v])
            | TFloat -> FloatList([v])
            | TInt -> FloatList([Float(float_of_value v)])
            | Collection _ -> ListCollection([v])
            | Fn (args_t,body_t) ->
                (* TODO: ListCollection(v) ? *)
                failwith "first class functions not supported yet"
            | TUnit -> failwith "cannot create singleton of unit expression"
        in Eval(fun th db ->
        begin match (get_eval el) th db with
        | Tuple _ | Float _ | Int _
        | FloatList _ | TupleList _
        | ListCollection _ | MapCollection _ as v -> rv_f v
        | SingleMapList l -> rv_f (ListCollection(smlc_to_c l))
        | SingleMap m -> rv_f (TupleList(smc_to_tlc m))
        | DoubleMap m -> rv_f (ListCollection(dmc_to_c m))
        | v -> failwith ("invalid singleton value: "^
                         (string_of_value v)^(get_expr expr))
        end)
    
    let combine_impl ?(expr = None) c1 c2 =
        begin match c1, c2 with
        | FloatList(c1), FloatList(c2) -> FloatList(c1@c2)
        | TupleList(c1), TupleList(c2) -> TupleList(c1@c2)
        | SingleMapList(c1), SingleMapList(c2) -> SingleMapList(c1@c2)
        | ListCollection(c1), ListCollection(c2) -> ListCollection(c1@c2)
        
        | SingleMap(m1), SingleMap(m2) ->
            TupleList((smc_to_tlc m1)@(smc_to_tlc m2))
        
        | DoubleMap(m1), DoubleMap(m2) ->
            ListCollection((dmc_to_c m1)@(dmc_to_c m2))

        | MapCollection(m1), MapCollection(m2) ->
            ListCollection((nmc_to_c m1)@(nmc_to_c m2))

        | _,_ -> failwith ("invalid collections to combine"^(get_expr expr))
        end

    let combine ?(expr = None) c1 c2 = Eval(fun th db ->
        combine_impl ~expr:expr ((get_eval c1) th db) ((get_eval c2) th db))

    (* Arithmetic, comparision operators *)
    (* op type, lhs, rhs -> op *)
    let op ?(expr = None) op_fn l r = Eval(fun th db ->
        op_fn ((get_eval l) th db) ((get_eval r) th db))

    (* Control flow *)
    (* predicate, then clause, else clause -> condition *) 
    let ifthenelse ?(expr = None) pred t e = Eval(fun th db ->
        let valid = match ((get_eval pred) th db) with
            | Float x -> x <> 0.0 | Int x -> x <> 0
            | _ -> failwith ("invalid predicate value"^(get_expr expr))
        in if valid then (get_eval t) th db else (get_eval e) th db)

    (* statements -> block *)    
    let block ?(expr = None) stmts =
        let idx = List.length stmts - 1 in
        Eval(fun th db ->
          let rvs = apply_fn_list th db stmts in List.nth rvs idx)
 
    (* iter fn, collection -> iteration *)
    let iterate ?(expr = None) iter_fn collection = Eval(fun th db ->
        let rv c = (c; Unit) in
        let aux fn l = rv (List.iter (fun v -> match fn v with
            | Unit -> ()
            | _ -> failwith ("invalid iteration"^(get_expr expr))) l)
        in
        begin match (get_eval iter_fn) th db, (get_eval collection) th db with
        | (Fun f, FloatList l) -> aux f l
        | (Fun f, TupleList l) -> aux f l
        | (Fun f, ListCollection l) -> aux f l

        | (Fun f, SingleMapList l) ->  rv (List.iter (fun (k,m) ->
            match f (Tuple(k@[SingleMap m])) with
            | Unit -> ()
            | _ -> failwith ("invalid iteration"^(get_expr expr))))

        (* Currently we convert to a list since SliceableMap doesn't implement
         * an 'iter' function. TODO: we could easily add this. *)
        | (Fun f, SingleMap m) -> aux f (smc_to_tlc m)
        | (Fun f, DoubleMap m) -> aux f (dmc_to_c m)
        | (Fun f, MapCollection m) -> aux f (nmc_to_c m)
        | (Fun _, _) -> failwith ("invalid iterate collection"^(get_expr expr))
        | _ -> failwith ("invalid iterate function"^(get_expr expr))
        end)

    (* Functions *)
    let bind_float expr arg th f =
        begin match arg with
        | AVar(var,_) -> Env.add (fst th) var (Float f), snd th
        | ATuple(vt_l) -> 
            failwith ("cannot bind a float to a tuple"^(get_expr expr))
        end

    let bind_tuple expr arg th t = begin match arg with
        | AVar(v,vt) ->
            begin match vt with
            | TTuple(_) -> fst th, (v,value_of_tuple t)::(snd th)
            | _ -> failwith ("cannot bind tuple to "^v^(get_expr expr))
            end
        | ATuple(vt_l) ->
            begin try 
            (List.fold_left2 (fun acc (v,_) tf -> Env.add acc v tf)
                (fst th) vt_l t, snd th)
            with Invalid_argument _ ->
                failwith ("could not bind tuple arg to value: "^
                          (string_of_value (value_of_tuple t))^(get_expr expr))
            end
         end

    let bind_value expr arg th m = begin match arg with
        | AVar(var,_) -> fst th, (var,m)::(snd th)
        | ATuple(vt_l) ->
            failwith ("cannot bind a value to a tuple"^(get_expr expr))
        end

    let bind_arg expr arg th v = begin match v with
        | Float x -> bind_float expr arg th x
        | Int x -> bind_float expr arg th (float_of_int x)
        | Tuple t -> bind_tuple expr arg th t
        | _ -> bind_value expr arg th v
        end

    (* arg, schema application, body -> fn *)
    let lambda ?(expr = None) arg body = Eval(fun th db ->
        let fn v = (get_eval body) (bind_arg expr arg th v) db
        in Fun fn)
    
    (* arg1, type, arg2, type, body -> assoc fn *)
    (* M3 assoc functions should never need to use slices *)
    let assoc_lambda ?(expr = None) arg1 arg2 body = Eval(fun th db ->
        let aux vl1 vl2 =
            let new_th = bind_arg expr arg2 (bind_arg expr arg1 th vl1) vl2 
            in (get_eval body) new_th db
        in let fn1 vl1 = Fun(fun vl2 -> aux vl1 vl2)
        in Fun fn1)

    (* fn, arg -> evaluated fn *)
    let apply ?(expr = None) fn arg = Eval(fun th db ->
        begin match (get_eval fn) th db, (get_eval arg) th db with
        | Fun f, x -> f x
        | _ -> failwith ("invalid function for fn app"^(get_expr expr))
        end)
    
    (* Collection operations *)
    
    (* map fn, collection -> map *)
    (* picks the return collection implementation based on the return type
     * of the map function *)
    let map ?(expr = None) map_fn map_rt collection =
        let rv_f v = match map_rt with
            | TFloat -> FloatList(v) 
            | TInt -> FloatList(List.map (fun x -> Float(float_of_value x)) v)
            | TTuple tl ->
                if is_flat map_rt then TupleList(v)
                else ListCollection(v)
            | Collection t -> ListCollection(v)
            | Fn (args_t,body_t) ->
                (* TODO: ListCollection(v) ? *)
                failwith "first class functions not supported yet"
            | TUnit -> failwith "map function cannot return unit type"
        in
        Eval(fun th db ->
        let aux fn  = List.map (fun v -> fn v) in
        match (get_eval map_fn) th db, (get_eval collection) th db with
        | Fun f, FloatList l -> rv_f (aux f l)
        | Fun f, TupleList l -> rv_f (aux f l)
        | Fun f, SingleMap m -> rv_f (aux f (smc_to_tlc m))
        | Fun f, DoubleMap m -> rv_f (aux f (dmc_to_c m))
        | Fun f, SingleMapList s -> rv_f (aux f (smlc_to_c s))
        | Fun f, ListCollection l -> rv_f (aux f l)
        | Fun f, MapCollection m -> rv_f (aux f (nmc_to_c m))
        | (Fun _, x) -> failwith ("invalid map collection: "^
                                  (string_of_value x)^(get_expr expr))
        | _ -> failwith ("invalid map function"^(get_expr expr)))
    
    (* agg fn, initial agg, collection -> agg *)
    (* Note: accumulator is the last arg to agg_fn *)
    let aggregate ?(expr = None) agg_fn init_agg collection = Eval(fun th db ->
        let aux fn v_f l = List.fold_left
            (fun acc v -> apply_list fn ((v_f v)::[acc])) 
            ((get_eval init_agg) th db) l
        in
        match (get_eval agg_fn) th db, (get_eval collection) th db with
        | Fun _ as f, FloatList l -> aux f (fun x -> x) l
        | Fun _ as f, TupleList l -> aux f (fun x -> x) l
        | Fun _ as f, ListCollection l -> aux f (fun x -> x) l
        | Fun _ as f, SingleMapList l ->
            aux f (fun (k,m) -> Tuple (k@[SingleMap m])) l
        | Fun _ as f, SingleMap m -> aux f (fun x -> x) (smc_to_tlc m)
        | Fun _ as f, DoubleMap m -> aux f (fun x -> x) (dmc_to_c m)
        | Fun _ as f, MapCollection m -> aux f (fun x -> x) (nmc_to_c m)
        | Fun _, v -> failwith ("invalid agg collection: "^
                                  (string_of_value v)^(get_expr expr))        
        | _ -> failwith ("invalid agg function"^(get_expr expr)))

    (* agg fn, initial agg, grouping fn, collection -> agg *)
    (* Perform group-by aggregation by using a temporary SliceableMap,
     * which currently is a hash table, thus we have hash-based aggregation. *)
    let group_by_aggregate ?(expr = None) agg_fn init_agg gb_fn collection =
        let apply_gb_agg init_v gb_acc agg_f gb_key =
            let gb_agg = if MC.mem gb_key gb_acc
                 then MC.find gb_key gb_acc else init_v in
            let new_gb_agg = agg_f gb_agg
            in MC.add gb_key new_gb_agg gb_acc
        in
        let apply_gb init_v agg_f gb_f gbc t =
            let gb_key = match gb_f t with | Tuple(t_v) -> t_v | x -> [x]
            in apply_gb_agg init_v gbc (fun a -> agg_f [t; a]) gb_key
        in
        Eval(fun th db ->
        let init_v = (get_eval init_agg) th db in
        match (get_eval agg_fn) th db,
              (get_eval gb_fn) th db,
              (get_eval collection) th db
        with
        | Fun f, Fun g, TupleList l -> TupleList(smc_to_tlc
            (List.fold_left (apply_gb
                init_v (apply_list (Fun f)) g) (MC.empty_map()) l))

        | Fun _, Fun _, v -> failwith ("invalid gb-agg collection: "^
            (string_of_value v)^(get_expr expr))
        
        | Fun _, gb, _ -> failwith ("invalid group-by function: "^
            (string_of_value gb)^(get_expr expr))
        
        | f,_,_ -> failwith ("invalid group by agg fn: "^
            (string_of_value f)^(get_expr expr)))


    (* nested collection -> flatten *)
    let flatten ?(expr = None) nested_collection =
        (*
        let flatten_inner_map k m acc =
          MC.fold (fun k2 v acc -> acc@[Tuple(k@k2@[v])]) acc m
        in
        *)
        Eval(fun th db ->
        match ((get_eval nested_collection) th db) with
        | FloatList _ ->
            failwith ("cannot flatten a FloatList"^(get_expr expr))
        
        | TupleList _ ->
            failwith ("cannot flatten a TupleList"^(get_expr expr))
        
        | SingleMap _ ->
            failwith ("cannot flatten a SingleMap"^(get_expr expr))

        | ListCollection l -> List.fold_left
            (combine_impl ~expr:expr) (List.hd l) (List.tl l)

        (* Note: for now we don't flatten tuples with collection fields,
         * such as SingleMapList, DoubleMap or MapCollections.
         * We need to add pairwith to first push the outer part of the
         * tuple into the collection, and then we can flatten.
         *)
        (* Flattening applied to SingleMapList and DoubleMap can create a
         * TupleList since the input is exactly of depth two.
        | SingleMapList l ->
            let r = List.fold_left
              (fun acc (k,m) -> flatten_inner_map k m acc) [] l
            in TupleList(r)

        | DoubleMap m ->
            let r = MC.fold flatten_inner_map [] m
            in TupleList(r)
        *)

        | _ -> failwith ("invalid collection to flatten"^(get_expr expr)))
        
        

    (* Tuple collection operators *)
    (* TODO: write documentation on datatypes + implementation requirements
     * for these methods *)
    let tcollection_op expr ex_s lc_f smc_f dmc_f nmc_f tcollection key_l =
        Eval(fun th db ->
        let k = apply_fn_list th db key_l in
        try begin match (get_eval tcollection) th db with
            | TupleList l -> lc_f l k
            | SingleMap m -> smc_f m k
            | DoubleMap m -> dmc_f m k
            | MapCollection m -> nmc_f m k
            | v -> failwith ("invalid tuple collection: "^(string_of_value v))
            end
        with Not_found ->
            failwith ("collection operation failed: "^ex_s^(get_expr expr)))

    (* map, key -> bool/float *)
    let exists ?(expr = None) tcollection key_l =
        let lc_f l k =
            let r = List.exists (fun t ->
                match_key_prefix k (tuple_of_value t)) l
            in if r then Int(1) else Int(0)
        in
        let mc_f m k_v = if MC.mem k_v m then Int(1) else Int(0)
        in tcollection_op expr "exists" lc_f mc_f mc_f mc_f tcollection key_l

    (* map, key -> map value *)
    let lookup ?(expr = None) tcollection key_l =
        (* returns the (unnamed) value from the first tuple with a matching key *)
        let lc_f l k =
            let r = List.find (fun t ->
                match_key_prefix k (tuple_of_value t)) l in
            let r_t = tuple_of_value r in
            let r_len = List.length r_t 
            in List.nth r_t (r_len-1)
        in
        let smc_f m k_v = MC.find k_v m in
        let dmc_f m k_v = SingleMap(MC.find k_v m) in
        let nmc_f m k_v = MC.find k_v m in
        tcollection_op expr "lookup" lc_f smc_f dmc_f nmc_f tcollection key_l
    
    (* map, partial key, pattern -> slice *)
    (* Note: converts slices to lists, to ensure expression evaluation is
     * done on list collections. *)
    let slice ?(expr = None) tcollection pkey_l pattern =
        let lc_f l pk = TupleList(List.filter (fun t ->
            match_key_prefix pk (tuple_fields (tuple_of_value t) pattern)) l)
        in
        let smc_f m pk = TupleList(smc_to_tlc (MC.slice pattern pk m)) in
        let dmc_f m pk = SingleMapList(dmc_to_smlc (MC.slice pattern pk m)) in
        let nmc_f m pk = ListCollection(nmc_to_c (MC.slice pattern pk m))
        in tcollection_op expr "slice" lc_f smc_f dmc_f nmc_f tcollection pkey_l


    (* Database retrieval methods *)
    let get_value ?(expr = None) (_) id = Eval(fun th db ->
        match DB.get_value id db with | Some(x) -> x | None -> Float(0.0))

    let get_in_map ?(expr = None) (_) (_) id =
        Eval(fun th db -> SingleMap(DB.get_in_map id db))
    
    let get_out_map ?(expr = None) (_) (_) id =
        Eval(fun th db -> SingleMap(DB.get_out_map id db))
    
    let get_map ?(expr = None) (_) (_) id =
        Eval(fun th db -> DoubleMap(DB.get_map id db))

    (* Database udpate methods *)
    let get_update_value th db v = (get_eval v) th db
    let get_update_key th db kl = apply_fn_list th db kl

    let get_update_map c pats = match c with
        | TupleList(l) -> MC.from_list (List.map kv_of_tuple l) pats
        | SingleMap(m) -> List.fold_left MC.add_secondary_index m pats
        | _ -> failwith "invalid single_map_t" 

    (* persistent collection id, value -> update *)
    let update_value ?(expr = None) id value = Eval(fun th db ->
        DB.update_value id (get_update_value th db value) db; Unit)
    
    (* persistent collection id, in key, value -> update *)
    let update_in_map_value ?(expr = None) id in_kl value = Eval(fun th db ->
        DB.update_in_map_value id
            (get_update_key th db in_kl)
            (get_update_value th db value) db;
        Unit)
    
    (* persistent collection id, out key, value -> update *)
    let update_out_map_value ?(expr = None) id out_kl value = Eval(fun th db ->
        DB.update_out_map_value id
            (get_update_key th db out_kl)
            (get_update_value th db value) db;
        Unit)
    
    (* persistent collection id, in key, out key, value -> update *)
    let update_map_value ?(expr = None) id in_kl out_kl value = Eval(fun th db ->
        DB.update_map_value id
            (get_update_key th db in_kl)
            (get_update_key th db out_kl)
            (get_update_value th db value) db;
        Unit)

    (* persistent collection id, update collection -> update *)
    let update_in_map ?(expr = None) id collection = Eval(fun th db ->
        let in_pats = DB.get_in_patterns id db
        in DB.update_in_map id
             (get_update_map ((get_eval collection) th db) in_pats) db;
        Unit)
    
    let update_out_map ?(expr = None) id collection = Eval(fun th db ->
        let out_pats = DB.get_out_patterns id db
        in DB.update_out_map id
             (get_update_map ((get_eval collection) th db) out_pats) db;
        Unit)

    (* persistent collection id, key, update collection -> update *)
    let update_map ?(expr = None) id in_kl collection = Eval(fun th db ->
        let out_pats = DB.get_out_patterns id db in
        DB.update_map id (get_update_key th db in_kl)
           (get_update_map ((get_eval collection) th db) out_pats) db;
        Unit)
    
    (*
    let ext_fn fn_id = failwith "External functions not yet supported"
    *)
    
    (* Top level code generation *)
    let trigger event rel trig_args stmt_block =
      Trigger (event, rel, (fun tuple db ->
        let theta = Env.make trig_args (List.map value_of_const_t tuple), [] in
          List.iter (fun cstmt -> match (get_eval cstmt) theta db with
            | Unit -> ()
            | _ -> failwith "trigger returned non-unit") stmt_block))

    (* Sources, for now files only. *)
    type source_impl_t = FileSource.t

    let source src framing (rel_adaptors : (string * adaptor_t) list) =
       let src_impl = match src with
           | FileSource(fn) ->
               FileSource.create src framing 
               (List.map (fun (rel,adaptor) -> 
                   (rel, (Adaptors.create_adaptor adaptor))) rel_adaptors)
               (list_to_string fst rel_adaptors)
           | SocketSource(_) -> failwith "Sockets not yet implemented."
           | PipeSource(_)   -> failwith "Pipes not yet implemented."
       in (src_impl, None, None)

    let main dbschema schema patterns sources triggers toplevel_queries =
      Main (fun () ->
        let db = DB.make_empty_db schema patterns in
        let (insert_trigs, delete_trigs) = 
          List.fold_left 
            (fun (insert_acc, delete_acc) trig ->
              let add_trigger acc =
                let (_, rel, t_code) = get_trigger trig
                in (rel, t_code)::acc
              in match get_trigger trig with 
              | (M3.Insert, _, _) -> (add_trigger insert_acc, delete_acc)
              | (M3.Delete, _, _) -> (insert_acc, add_trigger delete_acc))
          ([], []) triggers in
        let dispatcher =
          (fun evt ->
            match evt with 
            | Some(Insert, rel, tuple) when List.mem_assoc rel insert_trigs -> 
              ((List.assoc rel insert_trigs) tuple db; true)
            | Some(Delete, rel, tuple) when List.mem_assoc rel delete_trigs -> 
              ((List.assoc rel delete_trigs) tuple db; true)
            | Some _  | None -> false)
        in
        let mux = List.fold_left
          (fun m (source,_,_) -> FileMultiplexer.add_stream m source)
          (FileMultiplexer.create ()) sources
        in
        let db_tlq = List.map DB.string_to_map_name toplevel_queries in
          synch_main db mux db_tlq dispatcher StringMap.empty ())

    (* For the interpreter, output evaluates the main function and redirects
     * stdout to the desired channel. *)
    let output main out_chan = match main with
      | Main(main_f) ->
          Unix.dup2 Unix.stdout (Unix.descr_of_out_channel out_chan); main_f ()
      | _ -> failwith "invalid M3 interpreter main code"
      
   let to_string (code:code_t): string =
      failwith "Interpreter can't output a string"

   let debug_string (code:code_t): string =
      failwith "Interpreter can't output a string"
 
    let rec eval c vars vals db = match c with
      | Eval(f) -> f (Env.make vars (List.map value_of_const_t vals), []) db
      | Trigger(evt,rel,trig_fn) -> trig_fn vals db; Unit
      | Main(f) -> f(); Unit
end