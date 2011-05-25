open Algebra
open Types
open Compilepass
open Codegen

open Thriftgen
open Runtime
open Debugger

open Analysis
open Gui

(* TODO: typechecker *)

(* map expression list -> delta list * map expression list *)
let preprocess_files file_exprs_l =
    let m_expr_l = List.flatten file_exprs_l in
    let events_and_m_exprs =
        let events_l = List.map generate_all_events m_expr_l in
            List.fold_left2
                (fun acc ev_l me -> 
                    if List.mem_assoc ev_l acc then
                        let existing_me = List.assoc ev_l acc in
                            [(ev_l, (existing_me@[me]))]@(List.remove_assoc ev_l acc)
                    else
                        (acc@[(ev_l, [me])]))
                [] events_l m_expr_l
    in
    let event_groups = fst (List.split events_and_m_exprs) in
    let overlapping_groups =
        let intersect a b = List.flatten (List.map (fun x -> List.filter (fun y -> x = y) b) a) in
            List.map
                (fun g ->
                    let overlaps =
                        List.filter
                            (fun g2 -> List.length (intersect g g2) <> 0)
                            (List.filter (fun g2 -> not(g=g2)) event_groups)
                    in
                        (g, overlaps))
                event_groups
    in
    let disjoint_event_groups =
        List.for_all (fun (_,overlaps) -> List.length overlaps = 0) overlapping_groups
    in
        if disjoint_event_groups then
            List.map
                (fun (ev, me_l) -> (ev, fst (List.split (List.map rename_attributes me_l))))
                events_and_m_exprs
        else
            let string_of_delta = function | `Insert(n,_) -> "+"^n | `Delete(n,_) -> "-"^n in
            let string_of_event_group g = String.concat "," (List.map string_of_delta g) in
                print_endline "Overlaps:";
                List.iter
                    (fun (g,overlaps) ->
                        let g_str = string_of_event_group g in
                        let overlap_str =
                            String.concat ", "
                                (List.map (fun g2 -> "{"^(string_of_event_group g2)^"}") overlaps)
                        in
                            print_endline (g_str^": "^overlap_str))
                    overlapping_groups;
                raise (PlanException ("Map expressions depend on different events."))

let preprocess_query m_expr_l =
    let events = 
        let events_l = List.map generate_all_events m_expr_l in
            if (List.for_all (fun e -> e = (List.hd events_l)) (List.tl events_l)) then
                List.hd events_l
            else raise (PlanException ("Map expressions depend on different events."))
    in
    let (new_m_expr_l, _) = List.split (List.map rename_attributes m_expr_l) in
        (events, new_m_expr_l)

            
(* Sig: map expression -> (code_expression list * code_expression list) * compile trace
 * compile trace : (event path * (handler stages * (var * binding stages) list) list) list
 * Semantics: input query -> (declarations * (handler * event) list) * compile trace
 *)
(* Assumes input map expression has been typechecked *)
let compile_code_rec events pp_expr_l =

    print_endline ("Preprocessed events: "^
        (String.concat "," (List.map string_of_delta events)));

    List.iter 
        (fun pp_expr ->
            print_endline ("Preprocessed map expr:\n"^
                (indented_string_of_map_expression pp_expr 0)))
        pp_expr_l;

    (* Recursive compilation *)
    let (maps, map_vars, state_parents, event_path_stages, handlers_by_level_and_event) =
        compile_target_all pp_expr_l events
    in

    let base_rels = get_base_relations (List.hd pp_expr_l) in

    let type_list = generate_type_list pp_expr_l base_rels events in

    (* Code generation: maps, handlers *)
    let (recursive_map_decl_bodies, map_accessors, stp_decls) =
        generate_map_declarations maps map_vars state_parents type_list
    in

    let recursive_map_decls = List.map (fun d -> `Declare d) recursive_map_decl_bodies in

    let check_unique_declaration gdc_l =
        function
            | `Declare(d) ->
                  let compare_decl_id =
                      function
                          | `Declare(d2) -> 
                                (identifier_of_declaration d) = (identifier_of_declaration d2)
                          | _ -> raise (CodegenException("Invalid declaration: "))
                  in
                      not(List.exists compare_decl_id gdc_l)
            | _ -> raise (CodegenException("Invalid declaration: "))
    in

    let (global_decls, handler_and_events) =
	List.fold_left
	    (fun (gd_acc, handler_acc) (event, hb_l) ->
                if (List.length hb_l) > 0 then
                    begin
                        let (gdc_l, level_hc_l, bd_l, _, reused_bdc_l) =
                            List.fold_left
                                (fun (gdc_acc, hc_acc, bd_acc, bdc_acc, reuse_acc) (level,h,b) ->
                                    let (gdc, bdc, rdc, hc) =
                                        generate_code h b event true bdc_acc
                                            map_accessors stp_decls recursive_map_decls type_list
                                    in
                                    let unique_gdc =
                                        List.filter (fun d ->
                                            List.for_all (fun dl -> check_unique_declaration dl d) gdc_acc) gdc
                                    in
                                    let (new_gdc_acc, new_hc) =
                                        match hc with
                                            | `Profile _ -> (gdc_acc@[unique_gdc], hc)
                                            | _ ->
                                                  let prof_loc = generate_profile_id event in
                                                      ((gdc_acc@[(`Declare(`ProfileLocation prof_loc))::unique_gdc]),
                                                      `Profile("cpu", prof_loc, hc))
                                    in
                                    let new_bd = match h with
                                        | `Incr(_,_,_,bd,_) | `IncrDiff(_,_,_,bd,_) ->
                                              print_endline
                                                  ("Tracking bindings for "^
                                                      (indented_string_of_code_expression new_hc)^": ");
                                              print_endline (string_of_bindings bd);
                                              bd_acc@[(new_hc,bd)]
                                        | _ -> bd_acc
                                    in

                                    let new_reuse = List.filter (fun x -> not(List.mem x reuse_acc)) rdc in
                                        (new_gdc_acc, hc_acc@[(level, new_hc)], new_bd, bdc_acc@bdc, reuse_acc@new_reuse))

                                ([], [], [], [], []) hb_l
                        in

                        let merged_decls = List.flatten gdc_l in
                        let (merged_handlers, rebound_bd_l) =
                            let decl_filtered =
                                List.map (fun (level, c) ->
                                    (level, c, filter_declarations c reused_bdc_l))
                                    level_hc_l
                            in
                                List.fold_left
                                    (fun (hc_acc, bd_acc) (level, orig, opt) ->
                                        match opt with
                                            | None -> (hc_acc, List.remove_assoc orig bd_acc)
                                            | Some(c) ->
                                                  let has_bd = List.mem_assoc orig bd_acc in
                                                      if has_bd then
                                                          let bd = List.assoc orig bd_acc in
                                                              (hc_acc@[(level, c)],
                                                              (List.remove_assoc orig bd_acc)@[(c,bd)])
                                                      else (hc_acc@[(level, c)], bd_acc))
                                    ([], bd_l) decl_filtered
                        in
                        let unique_merged_decls =
                            List.filter (check_unique_declaration gd_acc) merged_decls
                        in

                        List.iter (fun d -> print_endline ("umd: "^(string_of_declaration d))) unique_merged_decls;
                        List.iter (fun (c, bd) -> print_endline
                            ("rebound: "^(string_of_code_expression c)^": "^(string_of_bindings bd)))
                            rebound_bd_l;

                        let handler_id = handler_name_of_event event in
                        let handler_args = 
                            match event with
                                | `Insert (_, fields) | `Delete (_, fields) -> fields
                        in

                        let get_global_used rv =
                            let find_global is_map id =
                                try
                                    Some (List.find
                                        (function
                                            | `Declare(`Map(mid,_,_)) -> is_map && mid = id
                                            | `Declare(`Variable(vid,_)) -> not(is_map) && vid = id
                                            | `Declare(_) -> false
                                            | _ -> raise (CodegenException ("Invalid declaration")))
                                        (recursive_map_decls@gd_acc@unique_merged_decls@reused_bdc_l))
                                with Not_found -> None
                            in
                                match rv with
                                    | `CTerm(`Variable(id)) -> find_global false id
                                    | `CTerm(`MapAccess (id, _)) -> find_global true id
                                    | _ -> None
                        in

                        let get_rv_type rv is_return_map global_used_opt =
                            let rv_type =
                                type_inf_arith_expr
                                    rv (recursive_map_decls@gd_acc@unique_merged_decls@reused_bdc_l)
                            in 
                                if is_return_map then 
                                    let fields =
                                        begin match global_used_opt with
                                            | Some(`Declare(`Map(mid, f, rt))) -> f
                                            | Some(_) | None ->
                                                  let msg =
                                                      ("Invalid map return val: "^
                                                          (string_of_arith_code_expression rv)^"\n")
                                                  in
                                                      print_endline msg;
                                                      raise (CodegenException msg)
                                        end
                                    in
                                        ctype_of_datastructure (`Map("", fields, rv_type))
                                else rv_type
                        in

                        (* Top level handler, i.e. handler at level 0, produces the query result *)
                        let (new_handlers, handler_returns) =
                            List.fold_left
                                (fun (hc_acc, ret_acc) (lv, hc) ->
                                    if lv = 0 then
                                        let rv = get_return_val hc in
                                        let (local, repl) = is_local_return_val hc rv in
                                            match rv with
                                                | `Eval x ->
                                                      let global_used = get_global_used x in
                                                      let is_ret_map =
                                                          print_endline ("Lookup: "^(string_of_code_expression hc));
                                                          List.iter
                                                              (fun (hc,bd) ->
                                                                  print_endline ("Assoc: "^(string_of_code_expression hc)^
                                                                      " binding: "^(string_of_bindings bd)))
                                                              rebound_bd_l;
                                                          if List.mem_assoc hc rebound_bd_l then
                                                              List.length (List.assoc hc rebound_bd_l) != 0
                                                          else false
                                                      in
                                                      let rv_type = get_rv_type x is_ret_map global_used in

                                                      let var = "queryResult"^(gen_var_sym()) in
                                                      let new_ret =
                                                          if is_ret_map then
                                                              match global_used with
                                                                  | Some(`Declare(`Map(id,_,_))) ->
                                                                        [(`ReturnMap id, rv_type)]

                                                                  | Some(_) | None ->
                                                                        let msg = ("Invalid map return val "^
                                                                            (string_of_arith_code_expression x))
                                                                        in
                                                                            print_endline msg;
                                                                            raise (CodegenException msg)

                                                          else if local && repl then [(`Return x, rv_type)]

                                                          else
                                                              begin match global_used with
                                                                  | Some(`Declare(`Variable(_))) -> [(`Return x, rv_type)]

                                                                  | Some(_) | None
                                                                        -> [(`Return (`CTerm(`Variable(var))), rv_type)]
                                                              end
                                                      in

                                                      let new_handler =
                                                          if local && repl then
                                                              let new_hc = remove_return_val hc in
                                                                  match new_hc with
                                                                      | `Block c -> c
                                                                      | y ->
                                                                            let msg =
                                                                                ("Invalid replaceable return val "^
                                                                                    (indented_string_of_code_expression y))
                                                                            in
                                                                                print_endline msg;
                                                                                raise (CodegenException msg)

                                                          else if is_ret_map then [remove_return_val hc]

                                                          else
                                                              begin match global_used with
                                                                  | Some(`Declare(`Variable(_))) -> [hc]
                                                                        
                                                                  | Some(_) | None ->
                                                                        let new_hc = replace_return_val hc (`Assign(var, x)) in
                                                                            [`Declare(`Variable(var, rv_type)); new_hc]
                                                              end
                                                      in
                                                          (hc_acc@new_handler, ret_acc@new_ret)
                                                | _ ->
                                                      let msg =
                                                          ("Invalid return val in top level handler:\n"^
                                                              (indented_string_of_code_expression hc))
                                                      in
                                                          print_endline msg;
                                                          raise (CodegenException msg)

                                    else (hc_acc@[hc], ret_acc))
                                ([], []) merged_handlers
                        in

                        let (handler_body_with_rv, handler_ret_type, handler_rv_decl) =
                            let (ret_code, new_ret_type, new_rv_decl) =
                                match handler_returns with
                                    | [] -> raise (CodegenException "No return values found!")
                                    | [(x,y)] -> (x,y,[])
                                    | _ ->
                                          let (rv_l, rt_l) =
                                              List.split (List.map
                                                  (fun (c,t) -> match c with
                                                      | `Return x -> (`Arith x, t)
                                                      | `ReturnMap mid -> (`Map mid, t))
                                                  handler_returns)
                                          in
                                          let rt = "tuple< "^(String.concat "," rt_l)^" >" in
                                          let (rt_var_opt, rt_decl) =
                                              let tuple_fields = 
                                                  let field_counter = ref 0 in
                                                      List.map2
                                                          (fun rv rt -> match rv with
                                                              | `Arith a ->
                                                                    begin match a with
                                                                        | `CTerm(`Variable(v)) -> ((v, rt), rv)
                                                                        | `CTerm(`MapAccess(mid,_)) -> ((mid, rt), rv)
                                                                        | _ -> 
                                                                              incr field_counter;
                                                                              (("f"^(string_of_int (!field_counter)), rt), rv)
                                                                    end
                                                              | `Map mid -> ((mid, rt), rv))
                                                          rv_l rt_l
                                              in
                                              let existing_decl =
                                                  List.filter
                                                      (function
                                                          | `Declare(`Tuple(_,f)) -> f = tuple_fields
                                                          | `Declare(_) -> false
                                                          | _ -> raise InvalidExpression)
                                                      gd_acc
                                              in
                                                  match existing_decl with
                                                      | [] ->
                                                            let tuple_var = gen_var_sym() in
                                                                (Some(tuple_var), [`Declare(`Tuple(tuple_var, tuple_fields))])

                                                      | [x] -> (None, [])
                                                      | _ -> raise DuplicateException
                                          in
                                              (`ReturnMultiple(rv_l, rt_var_opt), rt, rt_decl)
                            in
                                (reused_bdc_l@new_handlers@[ret_code], new_ret_type, new_rv_decl)
                        in

                        let handler_profile_loc_decl =
                            `ProfileLocation (generate_handler_profile_id handler_id)
                        in
                        let handler_code =
                            `Handler(handler_id, handler_args, handler_ret_type, handler_body_with_rv)
                        in
                            (gd_acc@[`Declare(handler_profile_loc_decl)]@unique_merged_decls@handler_rv_decl,
                            handler_acc@[(handler_code, event)])
                    end
                else
                    (gd_acc, handler_acc))

            ([], []) handlers_by_level_and_event
    in

    (* Organize declarations *)
    let all_decls = recursive_map_decls@global_decls in
    let (prof_loc_decls, other_decls) = List.partition
        (fun x -> match x with
            | `Declare(`ProfileLocation _) -> true | _ -> false) all_decls
    in
        ((prof_loc_decls@other_decls, handler_and_events), event_path_stages)


(* TODO: partitioning scheme for map expressions from multiple files *)
let compile_files file_exprs_l =
    (*
      let (events, new_m_exprs) = preprocess_query file_exprs_l in
          compile_code_rec events new_m_exprs
    *)
    let events_and_m_exprs = preprocess_files file_exprs_l in
        List.fold_left
            (fun ((gd_acc, h_acc), trace_acc) (events, m_expr_l) ->
                let ((gd,h), trace) = compile_code_rec events m_expr_l in
                    ((gd_acc@gd, h_acc@h), trace_acc@trace))
            (([],[]), []) events_and_m_exprs

(*
 * Object file compilation, i.e. handlers only.
 *)
let compile_query file_exprs_l out_file_name =
    let ((global_decls, handlers_and_events), _) = compile_files file_exprs_l in
    let out_chan = open_out out_file_name in
        generate_includes out_chan;

        (* output declarations *) 
	List.iter
	    (fun x -> output_string out_chan
		((indented_string_of_code_expression x)^"\n")) global_decls;
	output_string out_chan "\n";
        
        (* output handlers *)
        List.iter
            (fun (h, e) ->
	        output_string out_chan
		    ((indented_string_of_code_expression h)^"\n\n"))
            handlers_and_events;

        close_out out_chan


let write_trace_and_catalog file_name compile_trace =
    let catalog_fn =
        if Filename.check_suffix file_name "tc" then file_name
        else ((Filename.chop_extension file_name)^".tc")
    in
    let trace_catalog_out = open_out catalog_fn in
        (* compile_trace: (event path * (handler stages * binding stages list) list) list *)
        List.iter
            (fun (ep, stages_l) ->
                let event_path_name = String.concat "/"
                    (List.map (fun e -> match e with
                        | `Insert(r,_) -> "insert"^r
                        | `Delete(r,_) -> "delete"^r) ep)
                in

                (* write out compilation trace for each map expression for this event path *)
                let trace_fn = write_compilation_trace
                    (Filename.dirname catalog_fn) ep stages_l
                in
                    (* track trace file in catalog *)
                    output_string trace_catalog_out (event_path_name^","^trace_fn^"\n"))
            compile_trace;
        close_out trace_catalog_out

let write_profile_locations file_name =
    let profile_loc_out = open_out file_name in
        Hashtbl.iter
            (fun str_id loc_id ->
                output_string profile_loc_out ((string_of_int loc_id)^","^str_id^"\n"))
            code_locations;
        close_out profile_loc_out

let write_analysis_files handlers_and_events trace_file_name compile_trace =
    let analysis_base_fn = Filename.chop_extension trace_file_name in
    let query_id = Filename.basename analysis_base_fn in

        (* Output compilation trace if desired *)
        write_trace_and_catalog trace_file_name compile_trace;
    
        (* Output profile locations *)
        let prof_fn = analysis_base_fn^".prl" in
            write_profile_locations prof_fn;

            (* Output map+variable dependencies *)
            let graph_fn = analysis_base_fn^".deps" in
            let dep_graph =
                List.fold_left
                    (fun (node_acc, edge_acc) (h,e) ->
                        let (nodes,edges) = build_dependency_graph (get_dependencies h) node_acc edge_acc in
                            (nodes, edges))
                    ([], []) handlers_and_events
            in
                write_dependency_graph graph_fn query_id dep_graph;

                (* Output pseudocode *)
                let pseudo_fn = analysis_base_fn^".pseudo" in
                let (handler_l, _) = List.split handlers_and_events in
                    write_pseudocode pseudo_fn handler_l


let create_stream_type_info event relation_sources =
    let event_rel = get_bound_relation event in
        if List.mem_assoc event_rel relation_sources then
            let (stream_type_string,
                    source_type, source_args, tuple_type,
                    adaptor_type, adaptor_bindings,
                    thrift_tuple_namespace, stream_name)
              =
                (List.assoc event_rel relation_sources)
            in
            let stream_type =
                match stream_type_string with
                    | "file" -> File
                    | "socket" -> Socket
                    | _ -> raise (CodegenException
                          ("Invalid stream type string: "^stream_type_string))
            in
                (stream_name,
                (stream_type, source_type, source_args, tuple_type,
                adaptor_type, adaptor_bindings, thrift_tuple_namespace))
        else
            raise (CodegenException
                ("Could not find relation source for "^event_rel))

(*
 * Testing engine compilation: handlers, stream multiplexer, dispatcher, main
 *)

let compile_testing_engine file_exprs_l relation_sources out_file_name trace_file_name_opt =
    let query_base_path = Filename.chop_extension out_file_name in
    let query_id = Filename.basename query_base_path in
    let ((global_decls, handlers_and_events), compile_trace) = compile_files file_exprs_l in
    let code_out_chan = open_out out_file_name in

        generate_includes code_out_chan;
        generate_stream_engine_includes code_out_chan;

        (* output declarations *) 
	List.iter
	    (fun x -> output_string code_out_chan
		((indented_string_of_code_expression x)^"\n")) global_decls;
	output_string code_out_chan "\n";

        (* output handlers *)
        List.iter
            (fun (h, e) ->
	        output_string code_out_chan
		    ((indented_string_of_code_expression h)^"\n\n"))
            handlers_and_events;

        (match relation_sources with
            | [] ->
                  begin
                      print_endline "No sources found ... generating no op main.";
                      generate_noop_main code_out_chan
                  end

            | h::t ->
                  begin
                      let (_, (stream_type, _, _, _, _, _, _, _)) = h in
                      let (gen_init_fn, gen_main_fn) =
                          match stream_type with
                              | "file" -> 
                                    (generate_file_stream_engine_init, generate_file_stream_testing_main)

                              | "socket" -> 
                                    (generate_socket_stream_engine_init, generate_socket_stream_testing_main)

                              | _ -> raise (CodegenException ("Invalid stream source type: "^stream_type))
                      in

                          (* init *)
                          gen_init_fn code_out_chan
                              (List.map
                                  (fun (h,e) ->
                                      let (stream_name, stream_type_info) =
                                          create_stream_type_info e relation_sources
                                      in
                                          (stream_type_info, stream_name, h, e))
                                  handlers_and_events);

                          (* main *)
                          gen_main_fn query_id code_out_chan global_decls;

                          (* Output additional information from compilation *)
                          match trace_file_name_opt with
                              | None -> ()
                              | Some fn -> write_analysis_files handlers_and_events fn compile_trace
                  end);

        close_out code_out_chan
                  


(*
 * Engine compilation: handlers, stream multiplexer, dispatcher, thrift viewer, main
 *)

let compile_standalone_engine file_exprs_l relation_sources out_file_name trace_file_name_opt =
    let query_base_path = Filename.chop_extension out_file_name in
    let query_id = Filename.basename query_base_path in
    let ((global_decls, handlers_and_events), compile_trace) = compile_files file_exprs_l in
    let code_out_chan = open_out out_file_name in
    let thrift_file_name = query_base_path^".thrift"in
    let thrift_out_chan =  open_out thrift_file_name in
    let less_file_name = query_base_path^"_operators.cpp" in
    let less_out_chan = open_out less_file_name in

        generate_includes code_out_chan;
        generate_stream_engine_includes code_out_chan;
        generate_stream_engine_viewer_includes code_out_chan;

        (* output declarations *) 
	List.iter
	    (fun x -> output_string code_out_chan
		((indented_string_of_code_expression x)^"\n")) global_decls;
	output_string code_out_chan "\n";
        
        (* output handlers *)
        List.iter
            (fun (h, e) ->
	        output_string code_out_chan
		    ((indented_string_of_code_expression h)^"\n\n"))
            handlers_and_events;

        (* standalone engine *)
        let (_, (stream_type, _, _, _, _, _, _, _)) = List.hd relation_sources in
        let (gen_init_fn, gen_main_fn) =
            match stream_type with
                | "file" -> 
                      (generate_file_stream_engine_init, generate_file_stream_engine_main)

                | "socket" -> 
                      (generate_socket_stream_engine_init, generate_socket_stream_engine_main)

                | _ -> raise (CodegenException ("Invalid stream source type: "^stream_type))
        in

        (* init *)
        gen_init_fn code_out_chan
            (List.map
                (fun (h,e) ->
                    let (stream_name, stream_type_info) =
                        create_stream_type_info e relation_sources
                    in
                        (stream_type_info, stream_name, h, e))
                handlers_and_events);

        (* main *)
        gen_main_fn query_id thrift_out_chan code_out_chan less_out_chan global_decls;

        close_out thrift_out_chan;
        close_out code_out_chan;
        close_out less_out_chan;

        (* Output additional information from compilation *)
        match trace_file_name_opt with
            | None -> ()
            | Some fn -> write_analysis_files handlers_and_events fn compile_trace


(*
 * Debugger compilation: handlers, stream multiplexer, dispatcher, Thrift service
 *)
let compile_standalone_debugger file_exprs_l relation_sources out_file_name trace_file_name_opt =
    let query_base_path = Filename.chop_extension out_file_name in
    let query_id = Filename.basename query_base_path in
    let ((global_decls, handlers_and_events), compile_trace) = compile_files file_exprs_l in
    let code_out_chan = open_out out_file_name in
    let thrift_file_name = query_base_path^".thrift"in
    let thrift_out_chan =  open_out thrift_file_name in
    let less_file_name = query_base_path^"_operators.cpp" in
    let less_out_chan = open_out less_file_name in

        generate_includes code_out_chan;
        generate_stream_engine_includes code_out_chan;
        generate_stream_debugger_includes code_out_chan;

        (* Output declarations *) 
	List.iter
	    (fun x -> output_string code_out_chan
		((indented_string_of_code_expression x)^"\n")) global_decls;
	output_string code_out_chan "\n";
        
        (* Output handlers *)
        List.iter
            (fun (h, e) ->
	        output_string code_out_chan
		    ((indented_string_of_code_expression h)^"\n\n"))
            handlers_and_events;

        (* Standalone debugger *)
        let (_, (stream_type, _, _, _, _, _, _, _)) = List.hd relation_sources in
        let (gen_class_fn, gen_main_fn) =
            match stream_type with
                | "file" -> 
                      (generate_file_stream_debugger_class, generate_file_stream_debugger_main)

                | "socket" -> 
                      (generate_socket_stream_debugger_class, generate_socket_stream_debugger_main)

                | _ -> raise (CodegenException ("Invalid stream source type: "^stream_type))
        in

        (* Stream engine init: multiplexer, dispatcher *)
        let streams_handlers_and_events =
            List.map
                (fun (h,e) ->
                    let (stream_name, stream_type_info) =
                        create_stream_type_info e relation_sources
                    in
                        (stream_type_info, stream_name, h, e))
                handlers_and_events
        in

        (* Stream debugger and main *)
        let stream_debugger_class =
            gen_class_fn thrift_out_chan code_out_chan less_out_chan
                query_id global_decls streams_handlers_and_events
        in
            gen_main_fn code_out_chan stream_debugger_class;
            close_out thrift_out_chan;
            close_out code_out_chan;
            close_out less_out_chan;

            (* Output additional information from compilation *)
            match trace_file_name_opt with
                | None -> ()
                | Some fn -> write_analysis_files handlers_and_events fn compile_trace