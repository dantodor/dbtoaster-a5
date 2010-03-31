exception Assert0Exception of string

open Util

type relation_set_t = (Calculus.var_t list) StringMap.t

type map_key_binding_t = 
    Binding_Present of Calculus.var_t
  | Binding_Not_Present
type bindings_list_t = map_key_binding_t list
type map_ref_t = (Calculus.term_t * Calculus.term_t * bindings_list_t) 

type m3_condition_or_none =
    EmptyCondition
  | Condition of M3.calc_t

let rec to_m3_initializer 
  (map_definition: Calculus.readable_term_t) : 
    (M3.calc_t * relation_set_t) = 
  let rec cond_to_init phi base_term : 
    (M3.calc_t * relation_set_t * m3_condition_or_none) = 
      match phi with
        Calculus.RA_Leaf(Calculus.False) ->
          (M3.Const(M3.CFloat(0.0)), StringMap.empty, EmptyCondition)
      | Calculus.RA_Leaf(Calculus.True) -> 
          (base_term, StringMap.empty, EmptyCondition)
      | Calculus.RA_Leaf(Calculus.AtomicConstraint(c, t1, t2)) -> 
          let (lh_term, ra_map1) = (to_m3_initializer t1) in
          let (rh_term, ra_map2) = (to_m3_initializer t2) in
          let ra_map = 
            (MapAsSet.union_right ra_map1 ra_map2)
          in
            (match c with
                Calculus.Eq  -> 
                  (base_term, ra_map, Condition(M3.Eq(lh_term, rh_term)))
              | Calculus.Lt  -> 
                  (base_term, ra_map, Condition(M3.Lt(lh_term, rh_term)))
              | Calculus.Le  -> 
                  (base_term, ra_map, Condition(M3.Leq(lh_term, rh_term)))
              | Calculus.Neq -> 
                  failwith "TODO: Handle NEQ"
            )

      | Calculus.RA_Leaf(Calculus.Rel(mapn,map_vars)) -> 
          let (ma_term, ra_map) = (to_m3_map_access (
              (Calculus.make_term 
                (Calculus.RVal(
                  Calculus.Const(Calculus.Int(0))))), 
              (Calculus.make_term 
                (Calculus.RVal(
                  Calculus.External("INPUT_MAP_"^mapn, map_vars)))),
              (List.map (fun x -> Binding_Present(x)) map_vars)
            )) in
          (
            M3.Mult(M3.MapAccess(ma_term), base_term), 
            (MapAsSet.singleton mapn map_vars),
            EmptyCondition
          )
      
      | Calculus.RA_MultiNatJoin(t::[]) -> 
          cond_to_init t base_term

      | Calculus.RA_MultiNatJoin(t::l)  -> 
          let (term2, ra_map1, phi2) = 
            (cond_to_init (Calculus.RA_MultiNatJoin(l)) base_term) 
          in 
          let (term3, ra_map2, phi3) = 
            cond_to_init t term2
          in
          let ra_map = 
            (MapAsSet.union_right ra_map1 ra_map2)
          in
            ( match phi2 with
                EmptyCondition -> (term3, ra_map, phi3)
              | Condition(phi2_as_m3) -> 
                ( match phi3 with
                    EmptyCondition -> (term3, ra_map, phi2)
                  | Condition(phi3_as_m3) ->
                    (term3, ra_map, Condition(M3.Add(phi3_as_m3, phi2_as_m3)))
                )
            )

      | Calculus.RA_MultiNatJoin([]) -> 
          (base_term, StringMap.empty, EmptyCondition)

      | Calculus.RA_Neg(t)        -> failwith "TODO:Handle RA_Neg"
      | Calculus.RA_MultiUnion(l) -> failwith "TODO:Handle RA_MultiUnion"
  in
  let lf_to_init lf =
    match lf with 
        Calculus.AggSum(t,phi)            -> 
          let (base_term, ra_map1) = (to_m3_initializer t) in
          let (term, ra_map2, result_phi) = 
            (cond_to_init phi base_term) in
            (
              match result_phi with
                EmptyCondition -> (term, (MapAsSet.union_right ra_map1 ra_map2))
              | Condition(result_phi_as_m3) -> 
                  (
                    M3.IfThenElse0(result_phi_as_m3, term), 
                    (MapAsSet.union_right ra_map1 ra_map2)
                  )
            )
            
      | Calculus.Const(Calculus.Int c) ->
          (M3.Const(M3.CFloat(float_of_int c)), StringMap.empty)
      | Calculus.Const(Calculus.Double d) -> 
          (M3.Const(M3.CFloat(d)), StringMap.empty)
      | Calculus.Var(vn,vt) -> 
          (M3.Var(vn), StringMap.empty)
      | Calculus.Const(_) -> 
          failwith "TODO: Handle String,Long in to_m3_initializer"
      | Calculus.External(s,vs) -> 
          failwith "Error: Uncompiled calculus expression shouldn't have a map reference"
  in
  match map_definition with
      Calculus.RVal(lf) -> 
          lf_to_init lf

    | Calculus.RNeg(t)       -> 
          let (rhs, ra_map) = 
            (to_m3_initializer t) 
          in
            ((M3.Mult((M3.Const (M3.CFloat (-1.0))), rhs)), ra_map)

    | Calculus.RProd(t1::[]) ->
          (to_m3_initializer t1)

    | Calculus.RProd(t1::l)  -> 
        let (rhs, ra_map1) = 
          (to_m3_initializer (Calculus.RProd(l))) 
        in
        let (lhs, ra_map2) = 
          (to_m3_initializer t1) 
        in
          ((M3.Mult(lhs, rhs)), 
          (MapAsSet.union_right ra_map1 ra_map2))

    | Calculus.RProd([]) -> 
        (M3.Const(M3.CFloat(1.0)), StringMap.empty)

    | Calculus.RSum(t1::[]) ->
        (to_m3_initializer t1)

    | Calculus.RSum(t1::l) -> 
        let (rhs, ra_map1) = 
          (to_m3_initializer (Calculus.RProd(l))) 
        in
        let (lhs, ra_map2) = 
          (to_m3_initializer t1) 
        in
          ((M3.Add(lhs, rhs)), 
           (MapAsSet.union_right ra_map1 ra_map2))

    | Calculus.RSum([]) -> 
        (M3.Const(M3.CFloat(0.0)), StringMap.empty)

(********************************)
and split_vars (want_input_vars:bool) (vars:'a list) (bindings:bindings_list_t): 
               'a list = 
  List.fold_right2 (fun var binding ret_vars ->
    match binding with
    | Binding_Present(_)  -> if want_input_vars then ret_vars else var::ret_vars
    | Binding_Not_Present -> if want_input_vars then var::ret_vars else ret_vars
  ) vars bindings []

and to_m3_map_access 
  ((map_definition, map_term, bindings):map_ref_t) : 
  M3.mapacc_t * relation_set_t =
  
  let (mapn, mapvars) = (Calculus.decode_map_term map_term) in
  let (init_stmt, ret_ra_map) = 
    (to_m3_initializer (Calculus.readable_term map_definition)) 
  in
  let input_var_list = (split_vars true mapvars bindings) in
  let output_var_list = (split_vars false mapvars bindings) in
  ((mapn, 
    (fst (List.split input_var_list)), 
    (fst (List.split output_var_list)), 
    
      (*  Doing something smarter with the initializers... in particular, it 
          might be a good idea to see if any of the initialzers can be further 
          decompiled or pruned away.  For now, a reasonable heuristic is to use
          the presence of input variables *)
    (
      if (List.length input_var_list) > 0
      then init_stmt
      else M3.Const(M3.CFloat(0.0))
    )
  ), ret_ra_map);;

(********************************)

let rec to_m3 
  (t: Calculus.readable_term_t) 
  (inner_bindings:map_ref_t Map.Make(String).t) : 
  M3.calc_t * relation_set_t =
  
   let calc_lf_to_m3 lf =
      match lf with
         Calculus.AtomicConstraint(Calculus.Eq,  t1, t2) ->
            let (lhs, ra_map1) = (to_m3 t1 inner_bindings) in
            let (rhs, ra_map2) = (to_m3 t1 inner_bindings) in
            let ra_map = (MapAsSet.union_right ra_map1 ra_map2) in
              (M3.Eq (lhs, rhs), ra_map)
       | Calculus.AtomicConstraint(Calculus.Le,  t1, t2) ->
            let (lhs, ra_map1) = (to_m3 t1 inner_bindings) in
            let (rhs, ra_map2) = (to_m3 t1 inner_bindings) in
            let ra_map = (MapAsSet.union_right ra_map1 ra_map2) in
              (M3.Leq(lhs, rhs), ra_map)
       | Calculus.AtomicConstraint(Calculus.Lt,  t1, t2) ->
            let (lhs, ra_map1) = (to_m3 t1 inner_bindings) in
            let (rhs, ra_map2) = (to_m3 t1 inner_bindings) in
            let ra_map = (MapAsSet.union_right ra_map1 ra_map2) in
              (M3.Lt (lhs, rhs), ra_map)
         (* AtomicConstraint(Neq, t1, t2) -> ... *)
       | _ -> failwith "Compiler.to_m3: TODO cond"
   in
   let calc_to_m3 calc =
      match calc with
         Calculus.RA_Leaf(lf) -> calc_lf_to_m3 lf
       | _                    -> failwith "Compiler.to_m3: TODO calc"
   in
   let lf_to_m3 (lf: Calculus.readable_term_lf_t) =
      match lf with
         Calculus.AggSum(t,phi)             -> 
            let (lhs, ra_map1) = (calc_to_m3 phi) in
            let (rhs, ra_map2) = (to_m3 t inner_bindings) in
            let ra_map = (MapAsSet.union_right ra_map1 ra_map2) in
              ((M3.IfThenElse0(lhs,rhs)), ra_map)
       | Calculus.External(mapn, map_vars)      -> 
          (
            try
              let (access_term, ra_map) = 
                (to_m3_map_access 
                  (StringMap.find mapn inner_bindings)) 
              in
                (M3.MapAccess(access_term), ra_map)
            with Not_found -> 
              failwith ("Unable to find map '"^mapn^"' in {"^
                (StringMap.fold 
                  (fun k v accum -> accum^", "^k) 
                  inner_bindings "")^"}\n"
                )
          )
       | Calculus.Var(vn,vt)                -> 
            (M3.Var(vn), StringMap.empty)
       | Calculus.Const(Calculus.Int c)     -> 
            (M3.Const (M3.CFloat (float_of_int c)), StringMap.empty)
       | Calculus.Const(Calculus.Double c)  -> 
            (M3.Const (M3.CFloat c), StringMap.empty)
       | Calculus.Const(_)                  ->
            failwith "Compiler.to_m3: TODO String,Long"

   in
   match t with
      Calculus.RVal(lf)      -> lf_to_m3 lf
    | Calculus.RNeg(t1)      -> 
        let (rhs, ra_map) = (to_m3 t1 inner_bindings) in
        (M3.Mult((M3.Const (M3.CFloat (-1.0))), rhs), ra_map)
    | Calculus.RProd(t1::[]) -> (to_m3 t1 inner_bindings)
    | Calculus.RProd(t1::l)  -> 
        let (lhs, ra_map1) = (to_m3 t1 inner_bindings) in
        let (rhs, ra_map2) = (to_m3 (Calculus.RProd l) inner_bindings) in
        (M3.Mult(lhs, rhs), (MapAsSet.union_right ra_map1 ra_map2))
    | Calculus.RProd([])     -> 
        (M3.Const (M3.CFloat 1.0), StringMap.empty)
        (* impossible case, though *)
    | Calculus.RSum(t1::[])  -> 
        (to_m3 t1 inner_bindings)
    | Calculus.RSum(t1::l)   -> 
        let (lhs, ra_map1) = (to_m3 t1 inner_bindings) in
        let (rhs, ra_map2) = (to_m3 (Calculus.RSum l) inner_bindings) in
        (M3.Add(lhs, rhs), (MapAsSet.union_right ra_map1 ra_map2))
    | Calculus.RSum([])      -> 
        (M3.Const (M3.CFloat 0.0), StringMap.empty) 
        (* impossible case, though *)

let rec find_binding_calc_lf 
  (var: Calculus.var_t) 
  (calc: Calculus.readable_relcalc_lf_t) =
  
  (match calc with
      Calculus.False                                      -> false
    | Calculus.True                                       -> false
    | Calculus.AtomicConstraint(comp, inner_t1, inner_t2) -> 
          (find_binding_term var inner_t1) || (find_binding_term var inner_t2)
    | Calculus.Rel(relname, relvars)                      -> 
          List.fold_left (
            fun found curr_var -> (found || (curr_var = var))
          ) false relvars
  )
and find_binding_calc 
  (var: Calculus.var_t) 
  (calc: Calculus.readable_relcalc_t) =
  
  (match calc with
      Calculus.RA_Leaf(leaf)       -> find_binding_calc_lf var leaf
    | Calculus.RA_Neg(inner_calc)  -> find_binding_calc var inner_calc
    | Calculus.RA_MultiUnion(u)    -> 
          failwith "Compiler.ml: finding output vars in MultiUnion not implemented yet"
    | Calculus.RA_MultiNatJoin(j)  -> 
          List.fold_left (fun found curr_calc -> (found || (find_binding_calc var curr_calc))) false j
  )

and find_binding_term 
  (var: Calculus.var_t) 
  (term: Calculus.readable_term_t) = 
  
  (match term with 
      Calculus.RVal(Calculus.AggSum(inner_t,phi))  -> 
          (find_binding_calc var phi) || (find_binding_term var inner_t)
    | Calculus.RVal(Calculus.External(mapn, vars)) ->
          failwith "Compiler.ml: (extract_output_vars) A portion of an uncompiled term is already compiled!"
    | Calculus.RVal(Calculus.Var(v))   -> false
    | Calculus.RVal(Calculus.Const(c)) -> false
    | Calculus.RNeg(inner_t)           -> (find_binding_term var inner_t)
    | Calculus.RProd(inner_ts)         -> 
          List.fold_left (
            fun found curr_t -> (found || (find_binding_term var curr_t))
          ) false inner_ts
    | Calculus.RSum(inner_ts)          ->
          List.fold_left (
            fun found curr_t -> (found || (find_binding_term var curr_t))
          ) false inner_ts
  );;

let translate_var (calc_var:Calculus.var_t): M3.var_t = (fst calc_var)
let translate_var_type (calc_var:Calculus.var_t): M3.var_type_t = 
  match (snd calc_var) with
  | Calculus.TInt    -> M3.VT_Int
  | Calculus.TDouble -> failwith "Double types unsupported (CalcToM3.ml)"
  | Calculus.TLong   -> M3.VT_Int
  | Calculus.TString -> M3.VT_String
  

let translate_schema (calc_schema:Calculus.var_t list): M3.var_t list = 
  (List.map translate_var calc_schema)

let translate_map_ref ((t, mt): Compiler.map_ref_t): map_ref_t =
  (t, mt, (
    let outer_term = (Calculus.readable_term t) in 
    match (Calculus.readable_term mt) with
        Calculus.RVal(Calculus.External(n, vs)) -> 
              List.map 
                (fun var -> 
                    if (find_binding_term var outer_term) 
                    then Binding_Present(var)
                    else Binding_Not_Present
                ) vs
      | _ -> failwith "LHS of a map definition is not an External()"
  ))

module M3ProgInProgress = struct
  type mapping_params = (string * int list * int list)
  type map_mapping = mapping_params StringMap.t
  
  type possible_mapping = 
  | Mapping of mapping_params
  | NoMapping
  
  type trigger_map = (string * ((M3.var_t list) * (M3.stmt_t list))) list
  
  (* insertion triggers * deletion triggers * mappings * map definitions *)
  type t = trigger_map * trigger_map * map_mapping * 
           (string * map_ref_t) list * relation_set_t
  
  type insertion = (map_ref_t * M3.trig_t list * relation_set_t)
  
  let add_to_trigger_map rel vars stmts tmap =
    if List.mem_assoc rel tmap then
      let (tvars, tstmts) = List.assoc rel tmap in
      let joint_stmts = 
        (* We assume that we receive statements through build in the order that
           the statements should be executed in; This is rarely relevant but it
           is an atomicity guarantee made by M3.  The order with which we store
           relations is irrelevant, but within each relation's trigger, the
           statement order must be preserved *)
        tstmts @ 
          if tvars <> vars then
            List.map (M3Common.rename_vars vars tvars) stmts
          else
            stmts
      in
        (rel, (tvars, joint_stmts))::(List.remove_assoc rel tmap)
    else
       (rel, (vars, stmts))::tmap

  let init: t = ([], [], StringMap.empty, [], StringMap.empty)
    
  let build ((curr_ins, curr_del, curr_mapping, curr_refs, curr_ra_map):t)   
            ((descriptor, triggers, ra_map):insertion): t =
    let (query_term, map_term, map_bindings) = descriptor in
    let (map_name, map_vars) = Calculus.decode_map_term map_term in
    let mapping = 
      List.fold_left (fun result (cmp_term, cmp_map_term, cmp_bindings) ->
        if result == NoMapping then
          try 
            let (cmp_name, cmp_vars) = Calculus.decode_map_term cmp_map_term in
            let cmp_in_vars = split_vars true cmp_vars cmp_bindings in
            let cmp_out_vars = split_vars false cmp_vars cmp_bindings in
            let index_of (needle:Calculus.var_t)
                         (haystack:Calculus.var_t list) = 
              let (index, _) =
                (List.fold_left (fun (found, index) cmp -> 
                  ( (if cmp == needle then index else found),
                    index + 1
                  )
                ) (-1, 1) haystack)
              in
              if index == -1 then raise Calculus.TermsNotEquivalent
                                   (*shouldn't happen*)
              else index
            in
              Mapping(
                cmp_name,
                List.fold_right (fun in_var mapping -> 
                  (index_of in_var cmp_in_vars)::mapping
                ) (split_vars true map_vars map_bindings) [],
                List.fold_right (fun out_var mapping -> 
                  (index_of out_var cmp_out_vars)::mapping
                ) (split_vars false map_vars map_bindings) []
              )
          with Calculus.TermsNotEquivalent -> NoMapping
        else result
      ) NoMapping (snd (List.split curr_refs))
    in
      match mapping with
      | Mapping(m) -> 
        (
          curr_ins, (* an equivalent map exists. don't change anything *)
          curr_del,
          StringMap.add map_name m curr_mapping, (* just add a mapping *)
          curr_refs,
          curr_ra_map (* no new triggers == no new mappings *)
        )
      | NoMapping  -> 
        let (insert_trigs, delete_trigs) =
          List.fold_right (fun (pm, rel, vars, stmts) (ins, del) -> 
            match pm with 
            | M3.Insert -> ((add_to_trigger_map rel vars stmts ins), del)
            | M3.Delete -> (ins, (add_to_trigger_map rel vars stmts del))
          ) triggers (curr_ins, curr_del)
        in
        (
          insert_trigs, delete_trigs, 
          curr_mapping, 
          (map_name,descriptor)::curr_refs, 
          MapAsSet.union_right curr_ra_map ra_map
        )
  
  let get_rel_schema ((ins_trigs,del_trigs,_,_,_):t): 
      (M3.var_t list) StringMap.t =
    let gather_schema (rel_name, (rel_vars, _)) accum  =
      StringMap.add rel_name rel_vars accum
    in
      List.fold_right gather_schema ins_trigs (
        List.fold_right gather_schema del_trigs 
          StringMap.empty
      )
  
  let extend_with_ra_maps (base_accum:t): t =
    let (_,_,_,_,ra_map) = base_accum in
      StringMap.fold (fun relation schema accum ->
        build accum 
              ( (* The Map Definition term: Sum(1, Rel(RelVars)) *)
                translate_map_ref
                  ( Calculus.make_term (
                      Calculus.RVal(
                        Calculus.AggSum(
                          Calculus.RVal(Calculus.Const(Calculus.Double(1.0))),
                          Calculus.RA_Leaf(Calculus.Rel(relation, schema))
                        )
                      )
                    ),
                    Calculus.map_term relation schema
                  ),
                (* The triggers: On insert add 1, On delete sub 1 *)
                [ (
                  M3.Insert, relation, (translate_schema schema),
                  [ ( ( "INPUT_MAP_"^relation, [], 
                        (translate_schema schema), 
                        M3.Const(M3.CFloat(0.0))
                      ), (
                        M3.Const(M3.CFloat(1.0))
                      ) ) ] );
                  (
                  M3.Delete, relation, (translate_schema schema),
                  [ ( ( "INPUT_MAP_"^relation, [], 
                        (translate_schema schema), 
                        M3.Const(M3.CFloat(0.0))
                      ), (
                        M3.Const(M3.CFloat(-1.0))
                      ) ) ] )
                ],
                (* The RA Map; Should technically be negative, but eh *)
                StringMap.empty
              )
      ) ra_map base_accum
  
  let get_maps ((_, _, mapping, maps, _):t) : M3.map_type_t list =
    List.map (fun (map_name, (map_defn, map_term, map_bindings)) ->
      let (_, map_vars) = Calculus.decode_map_term map_term in
      (
        map_name, 
        List.map translate_var_type (split_vars true map_vars map_bindings),
        List.map translate_var_type (split_vars false map_vars map_bindings)
      )
    ) maps
  
  let get_triggers ((ins, del, mapping, _, _):t) : M3.trig_t list =
    let produce_triggers (pm:M3.pm_t) (tmap:trigger_map): M3.trig_t list =
      List.map (fun (rel_name, (rel_vars, triggers)) ->
        (pm, rel_name, rel_vars, 
          (List.map (fun trigger -> 
            (M3Common.rename_maps 
              (StringMap.map (fun (x,_,_)->x) mapping) trigger)
            ) triggers
          )
        )
      ) tmap
    in
      (produce_triggers M3.Insert ins) @ (produce_triggers M3.Delete del)
  
  let finalize (program:t) : M3.prog_t = 
    let prog_w_ra_maps = extend_with_ra_maps program in 
      (get_maps prog_w_ra_maps, get_triggers prog_w_ra_maps)

  let get_map_refs ((_,_,mappings,refs,_):t) : map_ref_t StringMap.t =
    let mapped_map_terms: map_ref_t StringMap.t = 
      StringMap.map (fun (base_map,_,_) -> List.assoc base_map refs) mappings
    in
      List.fold_left (fun ref_map (map, ref) ->
        StringMap.add map ref ref_map
      ) mapped_map_terms refs
      
    
  let generate_m3 (map_ref: Compiler.map_ref_t)
                  (triggers: Compiler.trigger_definition list)
                  (accum: t): t =
    let map_ref_as_m3 = translate_map_ref map_ref in
    let (target_access, ra_map1) = to_m3_map_access map_ref_as_m3 in
    let (update, ra_map2) = 
      (to_m3 (Calculus.readable_term (fst map_ref)) 
             (get_map_refs accum)
      ) in
    let triggers_as_m3 = 
      List.map (fun (delete, reln, relvars, params, expr) ->
        (
          (if delete then M3.Delete else M3.Insert),
          reln, (translate_schema relvars),
          [(target_access, update)]
        )
      ) triggers
    in
      build accum (
        map_ref_as_m3,
        triggers_as_m3,
        MapAsSet.union_right ra_map1 ra_map2
      )
end


(*
module SQLToM3 = struct
  type query_schema = ( 
    Calculus.readable_term_t list * 
    (string * Calculus.var_t list) list * 
    Calculus.var_t list
  ) list
  
  type db_sources = (
    string * M3.source_t * M3.framing_t * M3.adaptor_t
  ) list
  
  let compile_sql (buff:Lexing.lexbuff) 
                  (compiler_driver:(query_schema -> db_sources -> unit)) = 
    while (not buff.lex_eof_reached) do
      let (database,sources) = 
        (Sqlparser.dbtoasterSqlList Sqllexer.tokenize buff)
      in
        (compiler_driver database sources)
    done
  
  
  let calc_to_m3_driver (database:query_schema) (sources:db_sources):
    (M3.prog_t * db_sources) =
    let (queries, relations, params) = database in
    let (_, queries_with_terms) = 
      List.fold_left 
        (fun (count, queries_with_terms) curr_query ->
          ( count + 1,
            let bound_params = 
              List.fold_right
                (fun curr_param bound_params ->
                  if (CalcToM3.find_binding_term curr_param curr_query) then
                    curr_param::bound_params
                  else
                    bound_params
                ) [] params
            in
              (
                curr_query,
                Calculus.make_term 
                  Calculus.RVal(
                    Calculus.External("q_" ^ (string_of_int count), bound_params)
                  )
              )
          )
        ) queries []
    in
   let m3_prog = List.fold_left
      (fun full_m3_prog (query_term, map_term) ->
        let partial_m3_prog = 
          Compiler.compile_m3 relations map_term query_term
        in
          *)