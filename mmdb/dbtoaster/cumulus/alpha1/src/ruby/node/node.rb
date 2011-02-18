
require 'config/template';
require 'node/multikeymap';
require 'node/versionedmap';

###################################################

class LogNotification
  include CLogMixins;
  self.logger_segment = "Node";
    
  def initialize()
    nil
  end
  
  # for the semantics of Hold and Release, see RemoteCommitNotification
  def release
  end
  
  def fire(entry, value)
    info { entry.to_s + " = " + value.to_s }
  end
end

###################################################

class CommitNotification
  include CLogMixins;
  self.logger_segment = "Node";

  def initialize(record)
    @record = record;
  end
  
  # for the semantics of Hold and Release, see RemoteCommitNotification
  def release
  end
  
  def fire(entry, value)
    return if value.nil?;
    trace {"Fired Notification: " + entry.to_s + " = " + value.to_s }
    @record.discover(entry, value);
  end
end

###################################################

class PluralRemoteCommitNotification
  include CLogMixins;
  self.logger_segment = "Node";

  attr_reader :cmdid, :params, :subqueries;
  def initialize(cmdid, params)
    @cmdid, @params = cmdid, params.to_a;
    @subqueries = Array.new;
    @hold = true;
  end
  
  def register_subquery(fetch_component, destinations)
    sq = PluralRemoteCommitSubquery.new(fetch_component, self, destinations);
    @subqueries.push(sq);
    sq;
  end
  
  def finish_setup
    @hold = false;
    check_ready;
  end
  
  def check_ready
    return if @hold;
    if @subqueries.assert { |sq| sq.ready } then
      destinations = Hash.new { |h,k| h[k] = Hash.new };
      @subqueries.each do |sq|
        sq.load_destinations(destinations)
      end
      destinations.each_pair do |node, entries|
        unless $config.my_config["address"].equals(node) then
          debug { "Sending data for command #{@cmdid} to #{node}" };
          MapNode.getClient(node).push_get(entries, cmdid);
        end
      end
    end
  end
end

###################################################

class PluralRemoteCommitSubquery
  attr_reader :ready;
  
  def initialize(fetch_component, parent, expected_destinations)
    @fetch_component, @parent, @expected_destinations = fetch_component, parent, expected_destinations;
    @entries = Hash.new;
    @ready = false;
    raise "Error: NIL in Expected" if @expected_destinations.find { |t| t.nil? };
  end
  
  def fire(entry, value)
    @entries[entry] = value;
  end
  
  def release
    @parent.trace { "Subquery for cmd #{@parent.cmdid} released" }
    @ready = true;
    @parent.check_ready;
  end
  
  # computes entries (k-v pairs) per node for pushing data.
  # fetch_component members:
  # -- entry mappings are pairs of array indexes, (key index, paramlist index) 
  # -- target_partitions associates a partition to a node, note this assumes
  #    partition assignments are unique
  def load_destinations(destinations)
    params = @parent.params.clone;
    partition_size = $config.partition_sizes[@fetch_component.target.source];
    @expected_destinations.each { |dest| destinations[dest] }; # prime the destination buffer
    @entries.each_pair do |entry, value|
      @fetch_component.entry_mapping.each { |mapping| params[mapping[1]] = entry.key[mapping[0]]; } 
      target_partition = @fetch_component.target.partition(params, partition_size);
      @fetch_component.target_partitions.each_pair do |partition, node|
        raise "Error: NIL in LOAD" if node.nil?;
        if partition.zip(target_partition).assert { |partition| (partition[1] == -1) || (partition[1] == partition[0]) } then
          destinations[node][entry] = value;
        end
      end
    end
  end
end

###################################################

class QueryCompleteNotification
  include CLogMixins;
  self.logger_segment = "Node";

  attr_reader :cmdid, :params, :partition_accesses;
  def initialize(cmdid, params)
    @cmdid, @params = cmdid, params.to_a;
    @partition_accesses = Array.new;
    @hold = true;
  end

  def register_partition()
    p = PartitionAccessNotification.new(self);
    @partition_accesses.push(p);
    p;
  end
  
  def finish_setup
    @hold = false;
    check_ready;
  end
  
  def check_ready
    return if @hold;
    if @partition_accesses.assert { |dep| dep.ready } then
      results = @partition_accesses.inject(Hash.new) { |acc, p| acc.merge(p.results) }
      info { "Request #{@cmdid} sending #{results.size.to_s} results to #{$config.scholar.getHostName}." }
      info { results.collect { |e,v| e.to_s + " = " + v.to_s }.join(" / ") }
      Java::org::dbtoaster::cumulus::scholar::ScholarNode.getClient($config.scholar).push_results(results, @cmdid)
    end
  end
end

class PartitionAccessNotification
  attr_reader :ready, :results;
  
  def initialize(parent)
    @parent = parent;
    @results = Hash.new;
    @ready = false;
  end
  
  def fire(entry, value)
    @results[entry] = value;
  end
  
  def release
    @parent.trace { "Partition access for cmd #{@parent.cmdid} released" }
    @ready = true;
    @parent.check_ready;
  end
end

###################################################

class RemoteCommitNotification
  @@nodecache = Hash.new;

  include CLogMixins;
  self.logger_segment = "Node";
  
  def initialize(entries, destination, cmdid)
    @entries, @destination, @cmdid = Hash.new, destination, cmdid;
    entries.each do |e|
      @entries[e] = nil;
    end
    @count = @entries.size;
    @holding = 0;
  end
  
  # Hold and Release are used to deal with multitarget requests where the exact targetlist is unknown
  # After hold is called, the response will not be sent until release is called an equivalent number
  # of times.  If a fetch is multitarget, hold will be called once for every fetch and the corresponding
  # release will be called by the map when the set of results is known (but not necessarilly available)
  def hold
    trace { "Hold" }
    @holding += 1;
  end
  
  def release
    @holding -= 1;
    trace { "Release: " + @holding.to_s }
    @count = 0
    @entries.each_value do |v| 
      if v == nil then @count += 1; end; 
    end;
    check_ready;
  end
  
  def fire(entry, value)
    @count -= 1 unless (value == nil) || (!@entries[entry].nil?);
    @entries[entry] = value unless (value == nil) && (@entries.has_key? entry);
    check_ready;
  end
  
  private
  
  def check_ready
    debug { "RemoteCallback Check Ready: holding = " + @holding.to_s + "; entries left = " + @count.to_s }
    if (@holding <= 0) && (@count <= 0) then
      debug { "Connecting to " + @destination.to_s }
      peer = MapNode.getClient(@destination);
      peer.push_get(@entries, @cmdid);
      trace { "push finished" }
      true;
    end
  end
end

###################################################

class MapNodeStats
  attr_reader :name;
  attr_writer :name;
  
  include CLogMixins;
  self.logger_segment = "Node";

  def initialize(name, handler)
    @name, @handler = name, handler;
    @stats = @mass_puts = @puts = @fetches = @pushes = 0;
    @max_push = @push_size = 0;
  end
  
  def stat
    if ((@stats += 1) % 5000) == 0 then
      info { "Status: " + @name + ";" + 
        " put "      + @puts.to_s +
        " mass_put " + @mass_puts.to_s +
        " fetch "    + @fetches.to_s +
        " pushes "   + @pushes.to_s +
        " avg_push " + (@push_size.to_f / @pushes.to_f).to_s +
        " max_push " + @max_push.to_s + 
        " backlog " + @handler.backlog.to_s +
        " completed " + @handler.cleared_backlog.to_s }
    end
  end
  
  def mass_put
    @mass_puts += 1;
  end
  
  def put
    @puts += 1;
  end
  
  def fetch
    @fetches += 1;
  end
  
  def push(size)
    @pushes += 1;
    @push_size += size
    @max_push = size if @max_push < size;
  end
end

###################################################

class ValuationApplicator
  attr_reader :valuation, :log;
  
  include CLogMixins;
  self.logger_segment = "Node";

  def initialize(id, target, valuation, handler, log)
    @id, @target, @valuation, @handler, @log = id, target, valuation, handler, log;
    @final_val, @record = nil, nil;
    begin
      debug { "Init #{@valuation.target.source} eval #{@id}" }
      @final_val = @valuation.to_f
    rescue Exception => e
      # it's not ready
      raise e unless e.message.include? "Incomplete valuation"
      trace { "Valuation Init: #{e}" }
    end
  end
  
  def ready?
    not @final_val.nil?
  end
  
  def discover(key, value)
    trace { "Discovered that : #{key} = #{value}" }
    @valuation.discover(key, value)
    begin
      debug { "Discover #{@valuation.target.source} eval #{@id}" }
      @final_val = @valuation.to_f
      debug { "Single Put Update #{@id} : Map #{@valuation.target.source}[#{@target.key.to_a.join(",")}] += #{@final_val}" }
      if @record then
        @record.discover(@target.key, @final_val).finish;
        @handler.finish_valuating(@id);
      end
    rescue Exception => e
      # it's not ready
      raise e unless e.message.include? "Incomplete valuation"
      trace { "Valuation Discover: #{e}" }
    end
  end
  
  def finish_message
  end
  
  def expect_local
  end
  
  def find_local
  end
  
  def apply(partitions)
    if @final_val then
      debug { "Single Put Update #{@id} : Map #{@valuation.target.source}[#{@target.key.to_a.join(",")}] += #{@final_val}" }
      partitions[0].update(@target.key, @final_val);
      @handler.finish_valuating(@id);
    else
      trace { "Deferring change to Map #{valuation.target}" }
      @record = partitions[0].declare_pending;
    end
  end
end

###################################################

class MassValuationApplicator
  attr_reader :log, :valuation;
  
  include CLogMixins;
  self.logger_segment = "Node";
  
  def initialize(id, valuation, expected_gets, handler, log)
    @id, @handler, @log = id, handler, log;
    @expected_gets = expected_gets+1  #One, local get is implicit
    @final_val, @records = nil, nil;
    @expected_locals = 0;
    @valuation = valuation;
    trace { "Creating insert for Map #{valuation.target.source}; Cmd:#{@id}; expecting #{@expected_gets} gets" }
  end
  
  def discover(key, value)
    trace { "Discovered that #{key} = #{value}" }
    @valuation.discover(key, value)
  end
  
  def expect_local
    @expected_locals += 1;
  end
  
  def find_local
    @expected_locals -= 1;
    complete if ready?
  end
  
  def ready?
    (@expected_gets <= 0) && (@expected_locals <= 0);
  end
  
  def finish_message
    @expected_gets -= 1;
    debug { "Got message (#{@id}): #{@expected_gets} gets left, #{@expected_locals} locals left" }
    if ready? then
      complete;
      @records = nil;
    end
  end
  
  def apply(partition_list)
    if partition_list.find { |part| part.backlogged? } || (not ready?) then
      @records = partition_list.collect_hash { |part| [part.partition, part.declare_pending] };
      complete if ready?
    else
      partitions = partition_list.collect_hash { |part| [part.partition, part] };
      @valuation.foreach do |target, delta_value|
        trace { "Map #{valuation.target.source}[#{target.key.join(",")}] += #{delta_value}" }
        partition = target.partition(@handler.partition_sizes[target.source].to_java(:Long));
        partitions[partition].update(target.key, delta_value) if partitions.has_key? partition;
      end
      @handler.finish_valuating(@id);
    end
  end
  
  private
  
  def complete
    return unless @records;
    @valuation.foreach do |target, delta_value|
      trace { "Map #{valuation.target.source}[#{target.join(",")}] += #{delta_value}" }
      partition = target.partition(@handler.partition_sizes[target.source].to_java(:Long));
      @records[partition].discover(target.key, delta_value) if @records.has_key? partition;
    end
    @records.each_value { |record| record.finish }
    @handler.finish_valuating(@id);
  end
end

###################################################

class MapNodeHandler
  attr_reader :partition_sizes;
  
  include Java::org::dbtoaster::cumulus::node::MapNode::MapNodeIFace;
  include CLogMixins;
  self.logger_segment = "Node";

  def initialize(name)
    @maps = Hash.new { |h,k| h[k] = Hash.new };
    @templates = Hash.new;
    @cmdcallbacks = Hash.new;
    @stats = MapNodeStats.new(name, self);
    @partition_sizes = Hash.new;
    @log_maps = Array.new;
    @program = CompiledM3Program.new;
    #@queries = Hash.new;
  end
  
  ############# Internal Accessors
  
  def find_partition(source, key)
    raise SpreadException.new("find_partition for wildcard keys uses loop_partitions") if key.include?(-1);
    partition = NetTypes.compute_partition(key, @partition_sizes[source.to_i]).to_a;
    if (@maps.has_key? source.to_i) && (@maps[source.to_i].has_key? partition) then
      @maps[source.to_i][partition];
    else
      raise SpreadException.new("Request for unknown partition: " + source.to_s + "[" + partition.join(",") + "]; Known maps: " + @maps.collect {|k,v| k.to_s+"{"+v.keys.collect { |partid| "[#{partid.join(",")}]" }.join(";") + "}"}.join(", "));
    end
  end
  
  def loop_partitions(source, key)
    key = NetTypes.compute_partition(key, @partition_sizes[source.to_i]);
    trace { "loop_partitions: looking for map #{source} in {#{@maps.keys.join(",")}}" }
    @maps[source].each_pair do |map_key, partition|
      trace { "loop_partitions: [#{key.to_a.join(",")} =?= #{map_key.to_a.join(",")}]" }
      if key.zip(map_key).assert { |k, mk| (k == -1) || (k == mk) } then
        trace {"  ...yes!"}
        yield partition;
      end
    end
  end
  
  def create_partition(map, partition, size)
    @partition_sizes[map.to_i] = size;
    @maps[map.to_i][partition.collect { |partdim| partdim.to_i }] =
      MapPartition.new(map, partition,  @templates.values.collect do |t|
        t.access_patterns(map.to_i) end.concat!.uniq);
    debug { "Created partition #{@maps[map.to_i]} (size: #{size.join(",")})" }
  end
  
  def install_put_template(index, cmd)
    @templates[index.to_i] = cmd;
    @maps.each_pair do |map, partition_list| 
      partition_list.each_value do |partition|
        cmd.access_patterns(map).each do |pat| 
          debug { "Loading pattern: #{pat.join(",")}" }
          partition.add_pattern(pat)
        end
      end
    end
    cmd.compile_to_local(
      @program, 
      @maps.to_a.collect_hash { |map_partitions| [ map_partitions[0], map_partitions[1].keys ] }
    );
    debug {"Loaded Put Template ["+index.to_s+"]: " + @templates[index.to_i].to_s }
  end
  
  ############# Debugging Accessors
  
  def dump()
    @maps.keys.sort.collect do |map|
      @maps[map].collect do |key, partition|
        "Partition for Map " + partition.to_s + "\n" + partition.dump;
      end.join "\n"
    end.join "\n";
  end
  
  def localdump()
    info { dump() }
  end
  
  ############# Remote Accessor Utility Code

  def create_valuation(template, param_list)
    # Given a Template ID, find the corresponding template and produce a 
    # TemplateValuation (config/template.rb) for it.
    
    if ! @templates.has_key? template then 
      raise SpreadException.new("Unknown put template: " + template.to_s); 
    end
    
    template = @templates[template];
    valuation = TemplateValuation.new(template, template.param_map(param_list));
    
    #valuation.prepare(@templates[template].target.instantiate(version, valuation.params).freeze)
    
    valuation;    
  end
  
  def finish_valuating(id)
    @cmdcallbacks.delete(id);
  end
  
  def preload_locals(id, applicator)
    # initialize the template with values we can obtain locally
    # These are values that either...
    # 1) Exist in a local partition
    # 2) Have already been received thanks to some network hiccup.
    # we might end up changing required inside the loop, so we clone it first.
    
    #initialize the template with values we've already received
    
    if (@cmdcallbacks[id] != nil) then
      @cmdcallbacks[id].each do |response|
        response.each do |target_value|
          applicator.discover(target_value[0], target_value[1]);
        end
        applicator.finish_message;
      end
    end
    
    @cmdcallbacks.delete(id);
    
    # This is also treated as an implicit message to ourselves.  
    applicator.valuation.template.entries.each do |req|
      trace { "Checking for #{req}" }
      begin
        # If the value is known, then get() will fire immediately.
        # Note also that discover will fire the callbacks if it is necessary to do so.
        req_key = req.instantiated_key(applicator.valuation.params);
        loop_partitions(req.source, req_key) do |partition| 
          trace { "found partition : " + partition.to_s }
          applicator.expect_local
          partition.get(
            req_key,
            proc { |key, value| applicator.discover(MapEntry.new(req.source, key), value) },
            proc { applicator.find_local }
          )
        end;
      rescue Exception => e;
        # this just means that we don't have the partition for this requirement.
        if e.is_a? SpreadException then
          trace { "Preload Locals: #{e}" }
        else
          raise e;
        end
      end
    end
    applicator.finish_message;
    
    #register ourselves to receive updates in the future
    unless applicator.ready? then
      @cmdcallbacks[id] = applicator;
    end
  end
  
  ############# Synchronous Remote Accessors
  
  def get(target)
    ret = Hash.new()
    target.each do |t|
      raise SpreadException("Multitarget get requests are unsupported; use aggreget()") unless t.has_wildcards?;
      ret[t] = find_partition(t.source,t.key).get(t);
    end
    ret;
  end
  
  def aggreget(target, agg)
    target.collect_hash do |t|
      values = [];
      if t.has_wildcards? then
        loop_partitions(t.source, t.key) do |partition|
          values.concat(partition.get(t));
        end
      else
        values.push(find_partition(t.source, t.key).get(t));
      end
      [t, AggregateType.aggregate(agg, values)]
    end
  end
  
  ############# Asynchronous Remote Accessors
  
  def push_get(result, cmdid)
    debug {"Pushget: #{result.size} results for command #{cmdid} from #{Java::org::dbtoaster::cumulus::net::Server.activeSender}" }
    if cmdid == 0 then
      info {
        "  Fetch Results Pushed: " + 
        result.collect do |entry, val| entry.to_s + " = " + val.to_s end.join(", ")
      }
      return
    end
    
    if @cmdcallbacks[cmdid] == nil then
      # Case 1: we don't know anything about this put.  Save the response for later use.
      trace { "Pushget: Command unknown; first push" }
      @cmdcallbacks[cmdid] = Array.new;
      @cmdcallbacks[cmdid].push(result);
    elsif @cmdcallbacks[cmdid].is_a? Array then
      # Case 2: we haven't received a put message yet, but we have received other fetch results
      trace { "Pushget: Command unknown; subsequent push" }
      @cmdcallbacks[cmdid].push(result);
    else
      # Case 3: we have a put waiting for these results
      trace { "Pushget: Matched to command" }
      result.each do |target_value|
        @cmdcallbacks[cmdid].discover(target_value[0], target_value[1])
      end
      # it's possible that (for a non-looping put) discover will call finish_valuating,
      # so we need to check whether the callback still exists;
      @cmdcallbacks[cmdid].finish_message if @cmdcallbacks[cmdid];
      #unless @cmdcallbacks[cmdid] then
      #  @queries.each_key do |qcmd_id|
      #    qcmd_id
      #  end
      #end
    end
    @stats.push(result.size);
  end
  
  def update(relation, params, base_cmd)
    rules = @program.getRelationComponent(relation);
    debug { "Update (ID ##{base_cmd}): #{relation}(#{params.join(", ")})" }
    put_entries = Hash.new { |h,k| h[k] = PluralRemoteCommitNotification.new(k, params) }
    rules.fetches.each do |fetch_msg|
      if (destinations = fetch_msg.condition.match(params)) then
        loop_key = fetch_msg.entry.instantiated_key(params);
        loop_partitions(fetch_msg.entry.source, loop_key) do |partition|
          sq = put_entries[base_cmd + fetch_msg.id_offset].register_subquery(fetch_msg, destinations);
          trace { "Subquery for cmd #{base_cmd+fetch_msg.id_offset}: Send #{fetch_msg.entry} -> #{destinations.join(",")}" }
          partition.get(
            loop_key, 
            proc { |key, value| sq.fire(MapEntry.new(fetch_msg.entry.source, key), value) },
            proc { || sq.release }
          );
          @stats.fetch
        end
        @stats.fetch;
      end
    end
    put_entries.each_value { |rcn| rcn.finish_setup };

    debug { "Update (ID ##{base_cmd}): Done with fetches" }

    rules.puts.each do |put_msg|
      if (sources = put_msg.condition.match(params)) then
        unless put_msg.template.requires_loop? then
          debug { "Creating single put valuation, params: " + params.join(",") }
          valuation = put_msg.template.valuation(params);
          target = valuation.target;
          applicator = ValuationApplicator.new(
            base_cmd + put_msg.id_offset, target, valuation, self, false
          )
          debug { "Creating put: #{base_cmd + put_msg.id_offset} -> #{target}" }
          preload_locals(base_cmd + put_msg.id_offset, applicator);
          applicator.apply([find_partition(target.source, target.key)]);
          @stats.put;
        else
          valuation = put_msg.template.valuation(params);
          # okennedy: is the following comment true?  I don't think so
          # sources implicitly excludes the local node; we add a placeholder "expected_push" 
          # for ourselves so that nothing gets committed until we've had a chance to finish
          # reading everything there is to be read.  This "push" occurs (in preload_locals)
          # regardless of whether there is actually any local data useful for this put.
          applicator = MassValuationApplicator.new(
            base_cmd + put_msg.id_offset, valuation, sources, self, false
          ) 
          debug { "Creating mass-put: #{base_cmd + put_msg.id_offset} -> #{valuation.target}" }
          preload_locals(base_cmd + put_msg.id_offset, applicator);
          plist = Array.new;
          loop_partitions(valuation.target.source, valuation.target.key) { |partition| plist.push(partition) }
          applicator.apply(plist);
          @stats.mass_put;
        end
      end
    end
    @stats.stat;
  end
  
  def apply_query(mapid, cmdid, params)
    loop_key = @templates[mapid].target.instantiated_key(params);
    query_requests = Hash.new { |h,k| h[k] = QueryCompleteNotification.new(k, params) }
    loop_partitions(mapid, loop_key) do |partition|
      #debug { "Cmd #{basecmd} registering partition." }
      query_cb = query_requests[cmdid].register_partition()
      partition.get(loop_key,
        proc { |key,value|
          #debug { "PCB #{basecmd} #{key.join(",")} #{value}" }
          query_cb.fire(MapEntry.new(mapid, key), value) },
        proc { || query_cb.release });
    end
    query_requests.each_value { |qcn| qcn.finish_setup }
  end

  def query(mapid, params, basecmd)
    mapid_offset = @templates[mapid].index
#    pending_cmds = 0;
#    @cmdcallbacks.each_key do |cb_id| pending_cmd += 1 if cb_id<basecmd; end
#    if pending_cmds == 0 then
      apply_query(mapid, basecmd+mapid_offset, params);
#    else
#      @queries[basecmd] = [mapid, params, pending_cmds]
#    end
  end
  
  ############# Internal Control
  
  def backlog
    @maps.values.sum { |partitions| partitions.values.sum { |part| part.backlog } };
  end
  
  def cleared_backlog
    @maps.values.sum { |partitions| partitions.values.sum { |part| part.pending_cleared } };
  end
  
  def server_backlog
    if @server then @server.backlog else 0 end;
  end
  
  def setup(config, name)
    debug { "Initializing node: #{name}" }
    config.my_config["partitions"].each_pair do |map, partition_list|
      partition_list.each do |partition|
        create_partition(map, partition, config.partition_sizes[map])
      end
    end
    
    config.my_config["values"].each_pair do |map, keylist|
      keylist.each_pair do |key, value|
        find_partition(map, key).set(key, value);
      end
    end
    
    config.templates.each_pair do |tid, template|
      install_put_template(tid, template);
    end
    
    @log_maps.concat(config.log_maps);
  end
  
  def partitions  
    ret = Array.new;
    @maps.each_pair do |map, partitions|
      partitions.each_value do |partition|
        ret.push([partition.mapid, partition.partition]);
      end
    end
    ret;
  end
  
  def patterns
    @maps.collect do |map, partitions|
      [ map, partitions.values[0].patterns.keys ]
    end
  end
  
  def designate_server(server)
    @server = server;
  end
  
  def monitor_backlog(switch, local_id, water_marks = (7000...10000))
    return if @backlog_monitor;
    @backlog_monitor = Thread.new(self, switch, water_marks, local_id) do |handler, callback_addr, range, me|
      state = :low
      callback = nil;
      sleep 3;
      loop do
        begin
          backlog = handler.server_backlog
          if state == :low && backlog > range.end then
            debug { "Node #{me} requesting backoff" }
            callback = ChefNode.getClient(callback_addr) unless callback;
            callback.request_backoff(me);
            state = :high;
          elsif state == :high && backlog < range.begin then
            debug { "Node #{me} no longer needs backoff" }
            callback = ChefNode.getClient(callback_addr) unless callback;
            callback.finish_backoff(me);
            state = :low
          end
        rescue Exception => e
          error(e) { "Error in monitor_backoff" }
        end
        sleep 1;
      end
    end
  end
  
end

handler = MapNodeHandler.new($config.my_name);
handler.setup($config, $config.my_name);
return handler;