(**
   Global definitions for the schema of a database/set of streams
*)

open Types

(**
   Typing metadata for relations
*)
type rel_type_t = 
   | StreamRel           (** Dynamic relation.  The standard for DBT *)
   | TableRel            (** Static relation; DBT does not generate update 
                             triggers for Tables *)
(** 
   A Relation definition: Consists of [name] x [schema] x [typing metadata]
*)
type rel_t = 
   string *
   var_t list *
   rel_type_t

(**
   A triggered event
*)
type event_t =
 | InsertEvent of rel_t    (** An insertion into the specified relation *)
 | DeleteEvent of rel_t    (** A deletion from the specified relation *)
 | SystemInitializedEvent  (** Invoked when the system has been initialized, 
                               once all static tables have been loaded. *)

(**
   Tuple framing constructs for data sources.
*)
type framing_t =
   | Delimited of string (** Tuple frames are delimited by this string *)
   | FixedSize of int    (** Tuple frames are of fixed size *)

(**
   Data source constructs
*)
type source_t = 
   | NoSource                         (** The nullary data source. *)
   | FileSource of string * framing_t (** Read data from a file with the 
                                          specified framing construct *)
   | PipeSource of string * framing_t (** Read data from a UNIX pipe with the
                                          specified framing construct *)
   | SocketSource of Unix.inet_addr * int * framing_t 
                                      (** Create a server on the specified 
                                          address and port, and read data from
                                          client sockets on that port with the
                                          specified framing construct *)

(**
   An Adaptor, or mechanism for parsing tuple frames into data.  Adaptors 
   consist of a string name, and a list of string key/value pairs parameterizing 
   the adaptor.
*)
type adaptor_t = string * (string * string) list

(**
   Schema information for a given source.  For each source, a list of all 
   adaptors connected to that source, and the relation generated by that 
   adaptor.
*)
type source_info_t = (source_t * (adaptor_t * rel_t) list)

(**
   A database schema.  A list of all sources used by the engine.  Referential, 
   so it can be built up incrementally.
*)
type t = source_info_t list ref

(**
   An instance of the default empty database schema.
*)
let empty_db ():t = ref []

(**
   Add a relation to the indicated database schema.  Optionally include the 
   source and adaptor that will read into the relation.
   @param db      The database schema to modify
   @param source  (optional) The source from which the relation's tuples will be 
                  read.
   @param adaptor (optional) The adaptor that will parse the relation's tuples
   @param rel     The relation to add to the schema
*)
let add_rel (db:t) ?(source = NoSource) ?(adaptor = ("",[])) (rel:rel_t) = 
   if List.mem_assoc source !db then
      let source_rels = List.assoc source !db in
      db := (source, (adaptor, rel)::source_rels) ::
               (List.remove_assoc source !db)
   else
      db := (source, [adaptor, rel]) :: !db

(**
   Obtain the relations appearing in the indicated database schema.
   @param db   The database schema
   @return     A list of all relations appearing in [db]
*)
let rels (db:t): rel_t list =
   List.fold_left (fun old (_, rels) -> old@(List.map snd rels)) [] !db

(**
   Obtain the static (table) relations appearing in the indicated database 
   schema
   @param db   The database schema
   @return     A list of all static (table) relations appearing in [db]
*)
let table_rels (db:t): rel_t list =
   (List.filter (fun (_,_,rt) -> rt == TableRel) (rels db))

(**
   Obtain the dynamic (stream) relations appearing in the indicated database 
   schema
   @param db   The database schema
   @return     A list of all dynamic (stream) relations appearing in [db]
*)
let stream_rels (db:t): rel_t list =
   (List.filter (fun (_,_,rt) -> rt == StreamRel) (rels db))

(**
   Obtain the full relation object for a given relation name in the indicated
   database schema
   @param db   The database schema
   @param reln The name of a relation
   @return     The [rel_t] object for the relation named [reln] in [db]
   @raise Not_found If no relation named [reln] appears in [db]
*)
let rel (db:t) (reln:string): rel_t =
   List.find (fun (cmpn,_,_) -> reln = cmpn) (rels db)

(**
   Obtain the parameter list for the indicated event
   @param event An event
   @return      A list of all parameters taken by [event]
*)
let event_vars (event:event_t): var_t list =
   begin match event with
      | InsertEvent(_,relv,_) -> relv
      | DeleteEvent(_,relv,_) -> relv
      | SystemInitializedEvent -> []
   end

(**
   Variation-aware comparator for events
   @param a   An event
   @param b   An event
   @return    true if [a] and [b] refer to the same event, even if they differ
              on the details of this event.
*)
let events_equal (a:event_t) (b:event_t): bool =
   begin match (a,b) with
      | (SystemInitializedEvent, SystemInitializedEvent) -> true
      | (InsertEvent(an,_,_), InsertEvent(bn,_,_)) -> an = bn
      | (DeleteEvent(an,_,_), DeleteEvent(bn,_,_)) -> an = bn
      | _ -> false
   end

(**
   Generate the human-readable representation of a relation, in the form 
   [RelationName(col1, col2, col3, ...)].
   function is compatible with Calculusparser.
   @param rel   A relation
   @return      A human-readable representation of [rel]
*)
let string_of_rel ((reln,relsch,_):rel_t): string =
   (reln^"("^(ListExtras.string_of_list ~sep:", " string_of_var relsch)^")")

(**
   Obtain the name of a relation
   @param rel   A relation
   @return      The name of [rel]
*)
let name_of_rel ((reln,_,_):rel_t): string = reln

(**
   Obtain a whitespace-free identifier useable to describe an event.
*)
let name_of_event (event:event_t):string =
   begin match event with
      | InsertEvent(reln,_,_) -> "insert_"^reln
      | DeleteEvent(reln,_,_) -> "delete_"^reln
      | SystemInitializedEvent -> "system_ready_event"
   end

(**
   Obtain a whitespace-free identifier useable to describe the general type of 
   an event.
*)
let class_name_of_event (event:event_t):string =
   begin match event with
      | InsertEvent(_,_,_) -> "insert_tuple"
      | DeleteEvent(_,_,_) -> "insert_tuple"
      | SystemInitializedEvent -> "system_ready_event"
   end

(**
   Obtain a whitespace-free identifier useable to describe the 'relation' 
   triggering an event.
*)
let rel_name_of_event (event:event_t):string =
   begin match event with
      | InsertEvent(reln,_,_) 
      | DeleteEvent(reln,_,_) -> reln
      | SystemInitializedEvent -> "NULL_RELATION"
   end

(**
   Obtain the human-readable representation of an event.  The output of this 
   function is compatible with Calculusparser.
*)
let string_of_event (event:event_t) =
   begin match event with 
      | InsertEvent(rel)       -> "ON + "^(string_of_rel rel)
      | DeleteEvent(rel)       -> "ON - "^(string_of_rel rel)
      | SystemInitializedEvent -> "ON SYSTEM READY"
   end

(**
   Obtain a string representation of a framing construct constructor compatible 
   with Calculusparser.
   @param framing  A framing construct
   @return         The calculusparser-compatible string representation of
                   [framing] (to be used in a relation constructor)
                   
*)
let code_of_framing (framing:framing_t):string = begin match framing with
      | Delimited("\n") -> "LINE DELIMITED"
      | Delimited(x)    -> "'"^x^"' DELIMITED"
      | FixedSize(i)    -> "FIXEDWIDTH "^(string_of_int i)
   end

(**
   Obtain a string representation of a source construct constructor compatible 
   with Calculusparser.
   @param source   A source construct
   @return         The calculusparser-compatible string representation of
                   the constructor for [source] (to be used in a relation
                   constructor)
*)
let code_of_source (source:source_t):string = begin match source with
      | NoSource -> ""
      | FileSource(file, framing) -> 
         "FROM FILE '"^file^"' "^(code_of_framing framing)
      | PipeSource(file, framing) -> 
         "FROM PIPE '"^file^"' "^(code_of_framing framing)
      | SocketSource(addr, port, framing) -> 
         "FROM SOCKET "^(if addr = Unix.inet_addr_any then "" else
                         "'"^(Unix.string_of_inet_addr addr)^"' ")^
         (string_of_int port)^" "^(code_of_framing framing)
   end

(**
   Obtain a string representation of an adaptor construct constructor compatible 
   with Calculusparser.
   @param adaptor  An adaptor construct
   @return         The calculusparser-compatible string representation of
                   the constructor for [adaptor] (to be used in a relation
                   constructor)
*)
let code_of_adaptor ((aname, aparams):adaptor_t):string = 
   (String.uppercase aname)^(
      if aparams = [] then (if aname <> "" then "()" else "")
      else "("^(ListExtras.string_of_list ~sep:", " (fun (k,v) ->
         k^" := '"^v^"'") aparams)^")")

(**
   Obtain a string representation of a relation constructor compatible with 
   Calculusparser.
   @param rel   A relation
   @return      A calculusparser (and SQL)-compatible string representation of  
                the constructor for [rel], not including any DBToaster-specific
                constructs.
*)
let code_of_rel (reln, relv, relt): string =
   "CREATE "^(match relt with 
      | StreamRel -> "STREAM"
      | TableRel  -> "TABLE"
   )^" "^reln^"("^(ListExtras.string_of_list ~sep:", " (fun (varn,vart) ->
      varn^" "^(string_of_type vart)
   ) relv)^")"

(**
   Obtain a string representation of the full DBToaster-specific constructors 
   for all relations in the specified database schema
   @param sch  The database schema
   @return     A calculusparser (and SQL)-compatible string representation of
               the constructors for all the relations in [sch].
*)
let code_of_schema (sch:t):string =
   ListExtras.string_of_list ~sep:"\n\n" (fun (source, rels) ->
      let source_string = code_of_source source in
         ListExtras.string_of_list ~sep:"\n\n" (fun (adaptor,rel) ->
            (code_of_rel rel)^"\n  "^source_string^"\n  "^
            (code_of_adaptor adaptor)^";"
         ) rels
   ) !sch

(**
   Obtain a human-readable string representation of the specified database
   schema
   @param sch  The database schema
   @return     A human-readable string representation of [sch]
*)
let string_of_schema (sch:t):string =
   ListExtras.string_of_list ~sep:"\n" (fun (source, rels) ->
      begin match source with
         | NoSource -> "Sourceless"
         | FileSource(file, _) -> file
         | PipeSource(file, _) -> "| "^file
         | SocketSource(bindaddr, port, _) -> 
            if bindaddr = (Unix.inet_addr_any) then
               "*:"^(string_of_int port)
            else
               (Unix.string_of_inet_addr bindaddr)^":"^(string_of_int port)
      end^"\n"^
      (ListExtras.string_of_list ~sep:"\n" 
         (fun ((aname,aparams),(reln,relsch,relt)) ->
            "   "^reln^"("^
               (ListExtras.string_of_list ~sep:", " string_of_var relsch)^
            ")"^begin 
               if Debug.active "PRINT-VERBOSE" then
                  match relt with
                     | TableRel  -> " initialized using "
                     | StreamRel -> " updated using "
               else
                  match relt with
                     | TableRel  -> " := "
                     | StreamRel -> " << "
            end^aname^"("^(ListExtras.string_of_list ~sep:", "
               (fun (pname,pval) -> pname^" := '"^pval^"'") aparams
            )^")"
         ) rels
      )
   ) !sch
