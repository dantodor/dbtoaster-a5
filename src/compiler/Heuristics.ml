(**
   A module for deciding on how to materialize a given (delta) query. It is used
     by the Compiler module to produce a Plan.plan_t datastructure.
        
     Driven by a set of heuristics rules, this module provides 
     two main functions: 
     {ul
       {- {b should_update} decides whether it is more efficient to
          incrementally maintain the given query, or to reevaluate it upon 
          each trigger call }  
       {- {b materialize} transforms the input (delta) expression by replacing
          all relations with data structures (maps) }
     }
  *)

open Types
open Arithmetic
open Calculus
open CalculusDecomposition
open CalculusTransforms
open Plan

type ds_history_t = ds_t list ref
type term_list = expr_t list

(******************************************************************************)

(** A helper function for obtaining the variable list from 
    the optional event parameter. It calls Schema.event_vars 
    if the event is passed. *)
let extract_event_vars (event:Schema.event_t option) : (var_t list) =
   match event with 
      | Some(ev) ->  Schema.event_vars ev
      | None -> []

(** A helper function for extracting the relations from 
    the optional event parameter. *)
let extract_event_reln (event:Schema.event_t option) : (string option) =
   match event with
      | Some(Schema.InsertEvent((reln,_,_))) 
      | Some(Schema.DeleteEvent((reln,_,_))) -> Some(reln)
      | _  -> None

(** Obtain the human-readable representation of the optional event parameter. 
    It calls Schema.string_of_event if the event is passed. *) 
let string_of_event (event:Schema.event_t option) : string =
   match event with
      | Some(evt) -> Schema.string_of_event evt
      | _  -> "<None>" 

let string_of_expr = CalculusPrinter.string_of_expr
let string_of_vars = ListExtras.string_of_list string_of_var

let covered_by_scope scope expr = 
   let expr_ivars = fst (Calculus.schema_of_expr expr) in
      ListAsSet.diff expr_ivars scope = []


(** Reorganize a given expression such that: 1) terms depending only on the
    trigger variables are pulled out upfront; 2) the relation terms are 
    pushed to the left but after constant terms 3) comparisons and values 
    are pushed to the right. The partial order inside each of the group 
    (constants, relations, lifts, and values) is preserved. The method 
    assumes an aggsum-free product-only representation of the expression. *)
let prepare_expr (scope:var_t list) (expr:expr_t) : 
                 (term_list * term_list * term_list * term_list) =
   let expr_terms = CalcRing.prod_list expr in
   
   (* Extract constant terms *)
   let (const_terms, rest_terms) = 
      List.fold_left (fun (const_terms, rest_terms) term ->
         match CalcRing.get_val term with
            | Value(_) | Cmp(_, _, _) ->
               if covered_by_scope scope term
               then (const_terms @ [term], rest_terms)
               else (const_terms, rest_terms @ [term])
            | _ -> (const_terms, rest_terms @ [term])
      ) ([], []) expr_terms
   in
   (* Reorganize the rest *)
   let (rel_terms, lift_terms, value_terms) = 
       List.fold_left (fun (rels, lifts, values) term ->
          match CalcRing.get_val term with
             | Value(_) | Cmp(_, _, _) -> (rels, lifts, values @ [term])
             | Rel (_, _) | External (_) -> (rels @ [term], lifts, values)
(***** BEGIN EXISTS HACK *****)
             | Exists(_)
(***** END EXISTS HACK *****) 
             | Lift (_, _) -> (rels, lifts @ [term], values)
             | AggSum (_, _) ->
                failwith ("[prepare_expr] Error: " ^ 
                          "AggSums are supposed to be removed.")
      ) ([], [], []) rest_terms
   in
      (const_terms, rel_terms, lift_terms, value_terms)    

type materialize_opt_t = 
   | MaterializeAsNewMap
   | MaterializeUnknown


(** Split an expression into four parts: 
    {ol
      {li value terms that depends solely on the trigger variables }
      {li base relations, irrelevant lift expressions with respect to the 
          event relation that also contain no input variables, and 
          subexpressions with no input variables (comparisons, variables 
          and constants) }  
      {li lift expressions containing the event relation or input variables }
      {li subexpressions with input variables and the above lift variables } 
    } 
    Note: In order to minimize the need for IVC, if there is no relation at the 
    root level, then lift subexpressions containing irrelevant relations are 
    materialized separately. *)
let partition_expr (scope:var_t list) (event:Schema.event_t option) 
                   (expr:expr_t) : (expr_t * expr_t * expr_t * expr_t) =

   let (const_terms, rel_terms, lift_terms, value_terms) = 
      prepare_expr scope expr 
   in
   
   let ivc_opt_enabled = 
      not (Debug.active "HEURISTICS-IGNORE-IVC-OPTIMIZATION") 
   in
   let inputvar_allowed = 
      Debug.active "HEURISTICS-IGNORE-INPUTVAR-RULE"
   in
   let has_root_relation = (rel_terms <> []) in
   
   let final_const_expr = CalcRing.mk_prod const_terms in
      
   (* Pull in covered lift terms *)
   let (new_rl_terms, new_l_terms) = 
   begin 
      let rel_expr = CalcRing.mk_prod rel_terms in

      (* Sanity check - rel_expr should be covered by the scope *)
      if not (covered_by_scope scope rel_expr)
      then failwith "rel_expr is not covered by the scope."
      else     
         
      let rel_expr_ovars = snd (schema_of_expr rel_expr) in         
                  
      (* We have to decide on which lift terms should be  *)
      (* pulled in rel_terms. Here are some examples,     *)
      (* assuming inputvar_allowed = false                *)
      (* e.g. R(A,B) * (A ^= 0) --> Yes                   *)
      (*      R(A,B) * (D ^= 0) * (D ^= {A=C}) --> No     *)
      (*      R(A,B) * (C ^= 1) * (A ^= C) --> Yes        *)
      (*      R(A,B) * (C ^= D) * (A ^= C) --> No         *)
      (* Essentially, we perform graph decomposition over *)
      (* the lift and value terms. For each term group,   *)
      (* we make the same decision: either all terms are  *)
      (* going to be pulled in, or none of them. The      *)
      (* invariant that we want to preserve is the set of *)
      (* output variables of the relation term.           *)
      
                              
      (* Preprocessing step to mark those lifts that are *)
      (* going to be materialized separately for sure    *)
      let lift_terms_annot = List.map (fun l_term ->
         match CalcRing.get_val l_term with
(***** BEGIN EXISTS HACK *****)
            | Exists(subexpr)  
(***** END EXISTS HACK *****)
            | Lift(_, subexpr) -> 
               (* If there is no root relations, materialize *)
               (* subexp in order to avoid the need for IVC  *)
               if ivc_opt_enabled && not has_root_relation
               then (l_term, MaterializeAsNewMap)
               else

               let subexpr_rels = rels_of_expr subexpr in
               if subexpr_rels <> [] then begin

                  (* The lift subexpression containing the event *)
                  (* relation is always materialized separately  *)
                  let lift_contains_event_rel =
                     match extract_event_reln event with
                        | Some(reln) -> List.mem reln subexpr_rels
                        | None -> false
                  in
                  if lift_contains_event_rel
                  then (l_term, MaterializeAsNewMap)
                  else (l_term, MaterializeUnknown)
               end
               else (l_term, MaterializeUnknown)            
            | _ -> failwith "Not a lift term"         
      ) lift_terms in
      
      let value_terms_annot = List.map (fun v_term ->
         match CalcRing.get_val v_term with
            | Value(_) | Cmp(_, _, _) -> (v_term, MaterializeUnknown)
            | _ -> failwith "Not a value term"
      ) value_terms in
      
      (* Graph decomposition over the lift and value terms *)      
      let scope_lift =
         (* Scope is extended with rel_expr_ovars *) 
         ListAsSet.union scope rel_expr_ovars
      in
      let get_vars term_annot = 
         let i,o = C.schema_of_expr (fst term_annot) in 
         ListAsSet.diff (ListAsSet.union i o) scope_lift
      in     
      let graph_components = 
         HyperGraph.connected_unique_components get_vars 
            (lift_terms_annot @ value_terms_annot)
      in
      let get_graph_component term_annot = 
         List.find (fun terms_annot -> 
            List.mem term_annot terms_annot
         ) graph_components
      in
      
      List.fold_left (
         fun (r_terms, l_terms) (l_term, l_annot) ->
            match CalcRing.get_val l_term with
(***** BEGIN EXISTS HACK *****)
               | Exists(subexpr)  
(***** END EXISTS HACK *****)
               | Lift(_, subexpr) -> 
                  if l_annot = MaterializeAsNewMap 
                  then (r_terms, l_terms @ [l_term])
                  else begin 
                  try 
                     let graph_cmpnt = 
                        get_graph_component (l_term, l_annot) 
                     in
                     if (List.exists (fun (_, annot) -> 
                            annot = MaterializeAsNewMap) graph_cmpnt) 
                     then (r_terms, l_terms @ [l_term])
                     else begin
                        let graph_cmpnt_expr =  
                           CalcRing.mk_prod (List.map fst graph_cmpnt)
                        in
                        if covered_by_scope rel_expr_ovars graph_cmpnt_expr ||
                           inputvar_allowed
                        then (r_terms @ [l_term], l_terms)
                        else (r_terms, l_terms @ [l_term])
                     end   
                  with Not_found -> failwith "The lift term cannot be found."
                  end                 
               | _ -> failwith "Not a lift term"
      ) (rel_terms, []) lift_terms_annot                  
   end
   in
   
   let final_lift_expr = CalcRing.mk_prod new_l_terms in
   
   (* Pull in covered value terms *)
   let (new_rlv_terms, new_v_terms) =
   begin
      let rel_expr = CalcRing.mk_prod new_rl_terms in
   
      (* Sanity check - rel_expr should be covered by the scope *)
      if not (covered_by_scope scope rel_expr)
      then failwith "rel_expr is not covered by the scope."
      else                  

      let rel_lift_expr = CalcRing.mk_prod (new_rl_terms @ new_l_terms) in
      
      (* Sanity check - rel_lift_expr should be covered by the scope *)
      if not (covered_by_scope scope rel_lift_expr)
      then failwith "rel_lift_expr is not covered by the scope."
      else
      
      let rel_expr_ovars = snd (schema_of_expr rel_expr) in         
      let rel_lift_expr_ovars = snd (schema_of_expr rel_lift_expr) in
      
      List.fold_left (fun (r_terms, v_terms) v_term ->
         match CalcRing.get_val v_term with
            | Value(_) | Cmp (_, _, _) ->
               
               (* Sanity check - the term should be covered by the scope *)
               let scope_union = ListAsSet.union scope rel_lift_expr_ovars in
               if not (covered_by_scope scope_union v_term)
               then 
                  (print_endline ("Scope: " ^ (string_of_vars scope_union) ^
                                  "\nTerm: " ^ (string_of_expr v_term)); 
                  failwith "The value term is not covered by the scope.")
               else
               
               if covered_by_scope rel_expr_ovars v_term ||
                  inputvar_allowed
               then (r_terms @ [v_term], v_terms) 
               else (r_terms, v_terms @ [v_term])
            | _ -> failwith "Not a value term."
      ) (new_rl_terms, []) value_terms
   end
   in
   let final_rel_expr = CalcRing.mk_prod new_rlv_terms in
   let final_value_expr = CalcRing.mk_prod new_v_terms in
      (final_const_expr, final_rel_expr, 
       final_lift_expr,  final_value_expr)


(******************************************************************************)
(** For a given expression and a trigger event, decides whether it is more 
    efficient to incrementally maintain the expression or to reevaluate it 
    upon each trigger call. 
        
    The reason for making this decision is the following: If an expression 
    contains a lift subexpression (nested aggregate) with nonzero delta, 
    the overall delta expression is not simpler than the original expression.
    In such cases, it might be beneficial to maintain the expression 
    non-incrementally, recomputing it on every update.
            
    In general, the subexpressions of the given expression can be divided into 
    three categories:  
    {ol
       {li base relations, irrelevant lift expressions with respect to the 
           event relation that also contain no input variables, and 
           subexpressions with no input variables (comparisons, variables 
           and constants) }  
       {li lift expressions containing the event relation or input variables }
       {li subexpressions with input variables and the above lift variables } 
    }
    The rule for making the decision is the following:
    If there is an equality constraint between the base relations (category I) 
    and lift subexpressions (category II), i.e. the variables of the lift 
    subexpressions are also output variables of the base relations, then 
    the expression should be incrementally maintained. The rationale    behind 
    this decision is that deltas of the lift subexpressions affect only a subset
    of the tuples, thus bounding the variables used in the outside expression
    and avoiding the need to iterate over the whole domain of values.
    Otherwise, if there is no overlapping between the set of variables used 
    inside the lift subexpressions and the rest of the query, the expression 
    is more efficient to reevalute on each trigger call.
    
    Two special cases arise when the given expression does not contain lift
    subexpressions, or it does not contain relation subexpressions. In both 
    cases, this method suggests the incremental maintenance.
*)
let should_update (event:Schema.event_t) (expr:expr_t)  : bool =
   
   if (Debug.active "HEURISTICS-ALWAYS-UPDATE") then true
   (* "HEURISTICS-ALWAYS-REPLACE" makes sense only for TLQ. *)
   (* else if (Debug.active "HEURISTICS-ALWAYS-REPLACE") then false *)
   else
      
   let expr_scope = Schema.event_vars event in
   let (do_update, do_replace) = 
      (* Polynomial decomposition *)
      List.fold_left ( fun (do_update, do_replace) (term_schema, term) ->
        
         let term_opt = optimize_expr (expr_scope, term_schema) term in
    
         (* Graph decomposition *)
         let (do_update_graphs, do_replace_graphs) =  
            List.fold_left ( fun (do_update_graph, do_replace_graph) 
                                 (subexpr_schema, subexpr) ->
                            
               (* Subexpression optimization *)                    
               let subexpr_opt = 
                  optimize_expr (expr_scope, subexpr_schema) subexpr 
               in
               (* Split the expression into four parts *)
               let (_, rel_expr, lift_expr, _) = 
                  partition_expr expr_scope (Some(event)) subexpr_opt 
               in
               let rel_expr_ovars = snd (schema_of_expr rel_expr) in
               let lift_expr_ovars = snd (schema_of_expr lift_expr) in
               (* We assume that all equalities have been removed *)
               (* by the calculus optimizer*)
               let local_update_graph = 
                  ((rel_expr_ovars = []) || (lift_expr_ovars = []) ||
                   ((ListAsSet.inter rel_expr_ovars lift_expr_ovars) <> [])) 
               in
                  (do_update_graph || local_update_graph, 
                   do_replace_graph || (not local_update_graph))
            
            ) (false, false)
              (snd (decompose_graph expr_scope (term_schema, term_opt)))
         in
            (do_update || do_update_graphs, do_replace || do_replace_graphs)
                            
      ) (false, false) (decompose_poly expr)
   in
      if (do_update && do_replace) || (not do_update && not do_replace) 
      then (not (Debug.active "HEURISTICS-PREFER-REPLACE"))
      else do_update  
    
(******************************************************************************)

(** Perform partial materialization of a given expression according to 
    the following rules:
    {ol
       {li {b Polynomial expansion}: Before materializing, an expression is
        expanded into a flat ("polynomial") form with unions at the top. The
        materialization procedure is performed over each individual term. }
       {li {b Graph decomposition}: If some parts of the expression are 
       disconnected in the join graph, it is always better to materialise them 
       piecewise.}
       {li {b Decorrelation of nested subexpressions}: Lift expressions with 
       non-zero delta are always materialized separetely. } 
       {li {b No input variables}: No map includes input variables in order to
        prevent creation of large expensive-to-maintain domains. } 
       {li {b Factorization} is performed after the partial materialization 
       in order to maximise reuse of common subexpressions. }
    }
    @param scope     The scope in which [expr] is materialized
    @param db_schema Schema of the database
    @param history   The history of used data structures
    @param prefix    A prefix string used to name newly created maps
    @param event     A trigger event
    @param expr      A calculus expression
    @return          A list of data structures that needs to be 
                     materialized afterwards (a todo list) together with 
                     the materialized form of the expression. 
*)                                  
let rec materialize ?(scope:var_t list = []) (db_schema:Schema.t) 
                    (history:ds_history_t) (prefix:string) 
                    (event:Schema.event_t option) (expr:expr_t) : 
                    (ds_t list * expr_t) = 

   Debug.print "LOG-HEURISTICS-DETAIL" (fun () ->
      "[Heuristics] "^(string_of_event event)^
      "\n\t Map: "^prefix^
      "\n\t Expr: "^(string_of_expr expr)^
      "\n\t Scope: ["^(string_of_vars scope)^"]"
   );

   let expr_scope = ListAsSet.union scope (extract_event_vars event) in
   let (todos, mat_expr) = fst (
      (* Polynomial decomposition *)
      List.fold_left ( fun ((term_todos, term_mats), i) (term_schema, term) ->

         let term_opt = optimize_expr (expr_scope, term_schema) term in

            Debug.print "LOG-HEURISTICS-DETAIL" (fun () ->
               "[Heuristics] PolyDecomposition Before Optimization: " ^ 
               (string_of_expr term) ^
               "\n[Heuristics] PolyDecomposition + Optimization: " ^ 
               (string_of_expr term_opt) ^
               "\n\t Scope: [" ^ (string_of_vars expr_scope) ^ "]" ^
               "\n\t Schema: [" ^ (string_of_vars term_schema) ^ "]"
            ); 

            (* Graph decomposition *)
            let ((new_term_todos, new_term_mats), k) =  
            List.fold_left ( fun ((todos, mat_expr), j) 
                                 (subexpr_schema, subexpr) ->
                        
               (* Subexpression optimization *)                    
               let subexpr_opt = 
                  optimize_expr (expr_scope, subexpr_schema) subexpr 
               in
                        
               let subexpr_name = (prefix^(string_of_int j)) in
                                
               Debug.print "LOG-HEURISTICS-DETAIL" (fun () -> 
                  "[Heuristics] Graph decomposition: " ^ 
                  (string_of_expr subexpr) ^
                  "\n\t Scope: [" ^ (string_of_vars expr_scope)^"]" ^
                  "\n\t Schema: [" ^ (string_of_vars subexpr_schema) ^ "]" ^
                  "\n\t MapName: " ^ subexpr_name
               );
        
               let (todos_subexpr, mat_subexpr) = 
                  materialize_expr db_schema history subexpr_name event 
                                   expr_scope subexpr_schema subexpr_opt 
               in
                  Debug.print "LOG-HEURISTICS-DETAIL" (fun () -> 
                     "[Heuristics] Materialized form: " ^
                     (string_of_expr mat_subexpr)
                  );
                  ( ( todos @ todos_subexpr, 
                      CalcRing.mk_prod [mat_expr; mat_subexpr] ), 
                    j + 1)  
    
            ) (([], CalcRing.one), i)
              (snd (decompose_graph expr_scope (term_schema, term_opt)))
         in
            ( ( term_todos @ new_term_todos, 
                CalcRing.mk_sum [term_mats; new_term_mats] ), 
              k)
                    
      ) (([], CalcRing.zero), 1) (decompose_poly expr)
   )
   in begin
      if (Debug.active "HEURISTICS-IGNORE-FINAL-OPTIMIZATION") 
      then (todos, mat_expr)
      else let schema = snd (schema_of_expr mat_expr) in
           (todos, optimize_expr (expr_scope, schema) mat_expr)
   end
    
(* Materialization of an expression of the form mk_prod [ ...] *)   
and materialize_expr (db_schema:Schema.t) (history:ds_history_t) 
                     (prefix:string) (event:Schema.event_t option)
                     (scope:var_t list) (schema:var_t list) 
                     (expr:expr_t) : (ds_t list * expr_t) =

   (* Divide the expression into four parts *)
   let (const_expr, rel_expr, lift_expr, value_expr) = 
      partition_expr scope event expr 
   in        

   let (const_expr_ivars, const_expr_ovars) = schema_of_expr const_expr in
   let (rel_expr_ivars, rel_expr_ovars) = schema_of_expr rel_expr in
   let (lift_expr_ivars, lift_expr_ovars) = schema_of_expr lift_expr in
   let (value_expr_ivars, value_expr_ovars) = schema_of_expr value_expr in
      
   (* Sanity check - const_expr should not have input variables *)
   if ListAsSet.diff const_expr_ivars scope <> [] then begin
      print_endline ("Expr: " ^ string_of_expr const_expr);
      print_endline ("InputVars: " ^ string_of_vars const_expr_ivars);
      failwith "const_expr has input variables."
   end 
   else
   
   let scope_const = ListAsSet.union scope const_expr_ovars in

   if (Debug.active "HEURISTICS-IGNORE-INPUTVAR-RULE")
   then begin
      (* Sanity check - rel_exprs input variables should be in the scope *)
      if ListAsSet.diff rel_expr_ivars scope_const <> [] then begin
         print_endline ("Expr: " ^ string_of_expr rel_expr);
         print_endline ("InputVars: " ^ string_of_vars rel_expr_ivars);
         print_endline ("Scope: " ^ string_of_vars scope_const);
         failwith ("rel_expr has input variables not covered by the scope.")
      end
   end 
   else begin
      (* Sanity check - rel_exprs should not contain any input variables *) 
      if rel_expr_ivars <> [] then begin  
         print_endline ("Expr: " ^ string_of_expr rel_expr);
         print_endline ("InputVars: " ^ string_of_vars rel_expr_ivars);
         failwith ("rel_expr has input variables.") 
      end
   end;
                     
   (* Extended the schema with the input variables of other expressions *) 
   let rel_expected_schema = ListAsSet.inter 
        rel_expr_ovars 
        (ListAsSet.multiunion [  schema;
                                 scope_const;
                                 lift_expr_ivars;
                                 (* e.g. ON +S(dA)     *)
                                 (* R(A) * (C ^= S(A)) *)
                                 lift_expr_ovars;
                                 value_expr_ivars ]) 
   in
   (* If necessary, add an aggregation around the relation term *)
   let agg_rel_expr = 
      if ListAsSet.seteq rel_expr_ovars rel_expected_schema 
      then rel_expr
      else CalcRing.mk_val (AggSum(rel_expected_schema, rel_expr)) 
   in

   (* Extracted lifts are always materialized separately *)   
   let (todo_lifts, mat_lift_expr) = 
      if lift_expr = CalcRing.one then ([], lift_expr) else      
      fst (
          List.fold_left (fun ((todos, mats), (j, whole_expr)) lift ->
             match (CalcRing.get_val lift) with
(***** BEGIN EXISTS HACK *****)
                | Exists(subexpr) ->
                  let (todo, mat_expr) =
                     if rels_of_expr subexpr = []
                     then ([], subexpr)
                     else begin 
                        let scope_lift = 
                           ListAsSet.union scope_const
                                           (snd (schema_of_expr whole_expr)) in
                        materialize ~scope:scope_lift db_schema history 
                                    (prefix^"_E"^(string_of_int j)^"_") 
                                    event subexpr
                     end 
                  in
                  let mat_lift_expr = CalcRing.mk_val (Exists(mat_expr)) in
                     ((todos @ todo, CalcRing.mk_prod [mats; mat_lift_expr]), 
                      (j + 1, CalcRing.mk_prod [whole_expr; mat_lift_expr])) 
(***** END EXISTS HACK *****)
                | Lift(v, subexpr) ->
                  let (todo, mat_expr) =
                     if rels_of_expr subexpr = []
                     then ([], subexpr)
                     else begin 
                        let scope_lift = 
                           ListAsSet.union scope_const
                                           (snd (schema_of_expr whole_expr)) in
                        materialize ~scope:scope_lift db_schema history 
                                    (prefix^"_L"^(string_of_int j)^"_") 
                                    event subexpr
                     end 
                  in
                  let mat_lift_expr = CalcRing.mk_val (Lift(v, mat_expr)) in
                     ((todos @ todo, CalcRing.mk_prod [mats; mat_lift_expr]), 
                      (j + 1, CalcRing.mk_prod [whole_expr; mat_lift_expr]))
                | _  ->
                   Calculus.bail_out lift "Not a lift expression"
          ) (([], CalcRing.one), (1, agg_rel_expr)) 
            (CalcRing.prod_list lift_expr) 
      ) 
   in  
      
   Debug.print "LOG-HEURISTICS-DETAIL" (fun () -> 
      "[Heuristics]  Relation AggSum expression: " ^ 
      (string_of_expr agg_rel_expr) ^
      "\n\t Scope: [" ^ (string_of_vars scope_const) ^ "]" ^
      "\n\t Const OutVars: [" ^ (string_of_vars const_expr_ovars) ^ "]" ^
      "\n\t Lift InpVars: [" ^ (string_of_vars lift_expr_ivars) ^ "]" ^
      "\n\t Lift OutVars: [" ^ (string_of_vars lift_expr_ovars) ^ "]" ^
      "\n\t Value InpVars: [" ^ (string_of_vars value_expr_ivars) ^ "]" ^
      "\n\t Relation InVars: [" ^ (string_of_vars rel_expr_ivars) ^ "]" ^
      "\n\t Relation OutVars: [" ^ (string_of_vars rel_expr_ovars) ^ "]" ^
      "\n\t Original schema: [" ^ (string_of_vars schema) ^ "]" ^ 
      "\n\t Relation expected schema: [" ^
      (string_of_vars rel_expected_schema)^"]"
   ); 
         
   let (todos, complete_mat_expr) = 
      if (rels_of_expr rel_expr) = [] 
      then (todo_lifts, 
            CalcRing.mk_prod [ const_expr; 
                               agg_rel_expr; 
                               mat_lift_expr; 
                               value_expr ])
      else        
         (* Try to found an already existing map *)
         let (found_ds, mapping_if_found) = 
            List.fold_left (fun result i ->
               if (snd result) <> None then result 
               else (i, (cmp_exprs i.ds_definition agg_rel_expr))
            ) ( { ds_name = CalcRing.one; 
                 ds_definition = CalcRing.one}, None) !history
         in 
         begin match mapping_if_found with
            | None ->
               (* Compute the IVC expression *) 
               let ivc_expr = 
                  if (IVC.needs_runtime_ivc (Schema.table_rels db_schema)
                                             agg_rel_expr)
                  then (Calculus.bail_out agg_rel_expr
                     "Unsupported query.  Cannot materialize IVC inline (yet).")
                  else None
               in
                        
               Debug.print "LOG-HEURISTICS-DETAIL" (fun () ->
                  begin match ivc_expr with
                     | None -> "[Heuristics]  ===> NO IVC <==="
                     | Some(s) -> "[Heuristics]  IVC: \n" ^ (string_of_expr s)
                  end
               );
               let new_ds = {
                  ds_name = CalcRing.mk_val (
                     External(prefix,
                              rel_expr_ivars,
                              rel_expected_schema,
                              type_of_expr agg_rel_expr,
                              ivc_expr)
                  );
                  ds_definition = agg_rel_expr;
               } in
                  history := new_ds :: !history;
                  ([new_ds] @ todo_lifts, 
                   CalcRing.mk_prod [ const_expr; 
                                      new_ds.ds_name; 
                                      mat_lift_expr; 
                                      value_expr ])
                         
            | Some(mapping) ->
               Debug.print "LOG-HEURISTICS-DETAIL" (fun () -> 
                  "[Heuristics] Found Mapping to: " ^
                  (string_of_expr found_ds.ds_name)^
                  "      With: " ^
                  (ListExtras.ocaml_of_list 
                      (fun ((a, _), (b, _)) -> a ^ "->" ^ b) mapping)
               );
               (todo_lifts, 
                CalcRing.mk_prod [ const_expr; 
                                   (rename_vars mapping found_ds.ds_name); 
                                   mat_lift_expr; 
                                   value_expr ])
         end
   in
   (* If necessary, add aggregation to the whole materialized expression *)
   let (_, mat_expr_ovars) = schema_of_expr complete_mat_expr in
   let agg_mat_expr = 
      if ListAsSet.seteq mat_expr_ovars schema 
      then complete_mat_expr
      else CalcRing.mk_val (AggSum(schema, complete_mat_expr)) 
   in
      (todos, agg_mat_expr)

        