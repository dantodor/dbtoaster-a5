
require 'getoptlong';
require 'util/ok_mixins';
require 'config/config';
require 'config/template';
require 'fileutils';

class DBToaster
  attr_reader :compiled, :templates, :map_info, :test_directives,
    :slice_directives, :persist, :switch, :switch_forwarders, :switch_tree, :preload, :map_formulae;

  include CLogMixins;
  self.logger_segment = "Toaster";

  def initialize(toaster_cmd = "./dbtoaster.top -noprompt 2> /dev/null",
                 toaster_dir = $config.compiler_path)
    @nodes = Array.new;
    @partition_directives = Hash.new;
    @test_directives = Array.new;
    @slice_directives = Array.new;
    @keys = Hash.new;
    @persist = false;
    @compiled = nil;
    @switch = "localhost";
    @switch_forwarders = 0;
    @switch_tree = [];
    @preload = nil;
    @schemas = nil;
    @map_aliases = Hash.new;
    @map_formulae = nil;
    @query = "";
    
    debug { "#{toaster_dir}/#{toaster_cmd}" }
    local_dir = Dir.getwd()
    Dir.chdir(toaster_dir)
    @DBT = IO.popen(toaster_cmd, "w+");
    @DBT.write("open DBToasterTop;;\n");
    @DBT.write("#print_depth 10000;;\n");
    @DBT.write("#print_length 10000;;\n");
    @DBT.write("compile_sql_to_spread \"");
    Dir.chdir(local_dir);
  end
  
  ########################################################
  ## Pre-compilation accessors to load data in.
  ########################################################
  
  def load(sql_lines)
    r = sql_lines.collect do |l|
      if l[0..1] == "--" then l = l.split(" "); parse_arg(l.shift, l.join(" ")); nil
      else l.chomp end;
    end.compact.join(" ")
    select_stmt = r.match(/select[^;]+;/) 
    @query += select_stmt[0].gsub(/;/, "") unless select_stmt.nil?;
    @DBT.write(r);
    self;
  end
  
  def parse_arg(opt, arg)
    case opt
      when "--node"      then 
        @nodes.push(/ *([a-zA-Z0-9_]+) *@ *([a-zA-Z_\-0-9\.]+)(:([0-9]+))?/.match(arg).map(["name", "address", "dummy", "port"]));
      when "--switch"    then @switch = arg;
      when "--switch-forwarders" then @switch_forwarders = arg.to_i;
      when "--switch-tree" then @switch_tree = arg.split(',', 2).collect { |p| p.to_i }
      when "--partition" then 
        match = /Map *([a-zA-Z0-9_]+) *on *(.*)/.match(arg);
        raise "Invalid partition directive: " + arg unless match;
        @partition_directives[match[1]] = match[2].split(/, /).collect_hash do |column|
          sub_match = /([0-9]+) *(into *([0-9]+) *pieces|weight *by *([0-9]+))/.match(column)
          [sub_match[1].to_i, if sub_match[3].nil? then [:weight, sub_match[4].to_i] else [:exact, sub_match[3].to_i] end];
        end
      when "--test"      then @test_directives.push(arg);
      when "--slice"     then @slice_directives.push(arg);
      when "--persist"   then @persist = true;
      when "--key"       then 
        match = / *([^ \[]+) *\[ *([^\]]+) *\] *<= *([^ \[-]+) *\[ *([^\]]+) *\]/.match(arg)
        raise "Invalid key argument: " + arg unless match;
        @keys.assert_key(match[1]){ Hash.new }.assert_key(match[2]){ Hash.new }[match[3]] = [match[4]];
  #    else raise "Unknown option: " + opt;
      when "--preload"   then @preload = arg;
      when "--alias"     then @map_aliases = Hash[*arg.split(",").collect{ |x| x.strip }]
    end
  end
  
  ########################################################
  ## The compilation process
  ########################################################

  def toast(opts = Hash.new)
    @DBT.write("\";;\n");
    @DBT.close_write();
    data = @DBT.readlines;
    @DBT.close;
    
    begin    
      # line 1 is the annoying-ass header.  Delete it.  
      # Then, pull out the useful contents of list[****]
      # the contents, delimited by /"; *\n? *"/ can then be pulled out and each represents a line of template.
      # replace the "\t"s with actual tabs, and then ensure that each map reference includes at least one (constant if necessary) index.
      @compiled = data.collect do |l|
        l.chomp
      end.join("").gsub(/^.*string list[^\[]*\[([^#]*)"\].*/, "\\1").split("\";").collect do |l|
        l.gsub(/^ * *"([^"]*) *\n?/, "\\1\n").gsub(/\\t/, "	").gsub(/\[\]/, "[1]").gsub(/^ *\+/, "");
      end
      
      if @compiled.size < 2 then
        raise "Error compiling, no compiler output:" + data.join("");
      end

      # Make sure we have SOME nodes.
      raise "SQL file defines no nodes!  Either invoke toaster with --node, or include a --node directive in the SQL file" unless @nodes.size > 0;
  
      toast_templates;
      toast_schemas;
      toast_maps;

      generate_map_queries(data);
      
      @DBT = nil;
    rescue Exception => e
      error(e) { "Error toasting.  Compiler output: \n" + data.join("") };
    end
    self;
  end
  
  def toast_templates
    index = 0;

    templates_by_relation = Hash.new { |h, k| h[k] = Array.new }

    @compiled.collect do |l|
      debug { "Loading template: " + l }
      UpdateTemplate.new(l, index += 1);
    end.delete_if do |template|
      template.relation[0] == "-"[0];
    end.each do |template|
      rel_temps = templates_by_relation[ [template.relation, template.target.source] ];
      if rel_temps.empty? || (not rel_temps[0].conditions.conditions.empty?) then
        rel_temps.unshift(template);
      elsif (not template.conditions.conditions.empty?) then
        rel_temps.push(template);
      else
        rel_keys = rel_temps[0].entries.collect{ |e| e.key }.flatten.uniq
        new_key_names = template.entries.collect{ |e| e.key }.flatten.uniq.collect_hash do |key|
          if template.paramlist.include? key then 
            [key, rel_temps[0].paramlist[template.paramlist.index(key)]]
          else
            name = key;
            i = 1;
            while rel_keys.include? name
              name = "#{key}_#{i}"
              i += 1;
            end
            [key, name];
          end
        end
        rel_temps[0].entries.concat(template.entries)
        rel_temps[0].add_expression(template.expression);
      end
    end
    
    @templates = templates_by_relation.collect { |rel, tlist| tlist }.flatten
    
  end
  
  def toast_schemas
    @schemas = @templates.collect_hash do |t|
      [ t.relation, t.paramlist ];
    end
    
    # Do we need to normalize the schemas here?
  end
  def toast_maps
    # Now that we're done parsing inputs, we can do some munging of the partition and 
    # domain directives.  Specifically, for each map referenced in the templates, we
    # want to figure out the map's domain, and come up with a set of dimensions to 
    # partition the map over (we currently only partition over one dim).  If necessary
    # we resort to defaults so that each map has a value.
    #
    # We get the map names from UpdateTemplate, which keeps a hash map of name => ID
    @map_info =
      UpdateTemplate.map_names.collect do |map,info|
        total_product = 1;
        weight_count = 0;
        setup_partition = @partition_directives.fetch(map) { { 0 => [:weight, 1] } }
        setup_partition.each_pair { |col, dist| weight_count += 1 if dist[0] == :weight; total_product *= dist[1].to_i };
        
        split_per_weight = (@nodes.size.to_f / total_product.to_f).to_i;
        split_per_weight = split_per_weight ** (1.0/weight_count.to_f) if weight_count > 0;
        
        
        final_partitions = (0...info["params"].to_i).collect do |col|
          ptype, magnitude = *setup_partition.fetch(col, [:exact, 1]);
          
          case ptype
            when :weight then (0 ... (magnitude * split_per_weight))
            when :exact  then (0 ... magnitude)
          end.to_a
        end.cross_product;
        raise SpreadException.new("Incorrect number of partitions created: Expected: " + @nodes.size.to_s + "; Generated: " + final_partitions.size.to_s) unless final_partitions.size == @nodes.size;
        
        [ info["id"].to_i,
          { "map"        => map, 
            "id"         => info["id"].to_i, 
            "num_keys"   => info["params"].to_i,
            "partition"  => final_partitions,
            "reads_from" => Array.new,
            "writes_to"  => Array.new,
            "discarded"  => false
          }
        ]
      end.collect_hash
  end

  def normalize_keys(keys)
    keys.collect do |k|
      case k when TemplateVariable then k.name;
        else k.to_s;
      end
    end
  end

  # Generate bootstrap queries
  def generate_map_queries(compiler_output)
    compiled_maps = compiler_output.select do |l|
      l =~ /Adding compilation of/
    end.collect do |l|
      n = l.chomp.gsub(/Adding compilation of ([a-zA-Z0-9]+): .*/, "\\1")
    end
    
    @map_formulae = Hash[*compiler_output.select do |l|
        if l =~ /Creating map/ then 
          n = l.chomp.gsub(/Creating map ([a-zA-Z0-9]+) .*/, "\\1")
          not(compiled_maps.index(n).nil?)
        else false end 
      end.collect do |l|
        
        n,t = l.chomp.gsub(/Creating map ([a-zA-Z0-9]+) for term (.*)/, "\\1 \\2").split(" ",2)

        debug { n+": "+t }
        
        # Substitutions for variables -> params (i.e. dom vars)
        key_param_subs = Hash.new
        pred_var_subs = Hash.new
        param_constraints = Hash.new
        
        # Separate aggregate vs. relational part
        agg,rel_t = t.gsub(/AggSum\((.*)\)/, "\\1").split(",", 2)
        
        t_rels = []
        t_preds = []
        rel_t.split(" and ").each do |t|
          if t =~ /\(/ then t_rels.push(t) else t_preds.push(t) end 
        end

        rels = t_rels.collect do |r|
          # Separate relation names and fields
          rel_n, rel_f = r.gsub(/([a-zA-Z0-9]+)\(([^\)]*)\)/,"\\1 \\2").split(" ",2)
          rel_alias = @map_aliases.key?(rel_n) ? @map_aliases[rel_n] : nil
          fields_and_prefixes = rel_f.split(",").collect do |f|
              x=f.strip;
              prefix = if (p_idx = x.index('__')).nil? then "" else x[0,p_idx] end; 
              [x,prefix]
            end
          
          # Check if prefix matches schema alias, otherwise add predicate
          invalid_indexes = []
          domains = Hash.new
          fields_and_prefixes.each_index do |i|
            f, p = fields_and_prefixes[i]
            if p != rel_alias then invalid_indexes.push(i) end
          end;
          predicates =
            invalid_indexes.collect do |i|
              f,p = fields_and_prefixes[i]
              orig_f = if @schemas.key? rel_n then @schemas[rel_n][i]
                  else raise "Could not find schema for relation #{rel_n}"
                end

              unifications = []
              norm_orig_f = orig_f.sub(/__/, ".")
              new_f =
                if f =~ /^x_/ then
                  attr_idx = f.index('__')-1
                  dom_rel_start = f[0,attr_idx].rindex('_')+1
                  dom_rel_alias = f[dom_rel_start..attr_idx]
                  dom_attr = f[attr_idx+1..-1]
                  dom_rel = if @map_aliases.value?(dom_rel_alias)
                    then @map_aliases.index(dom_rel_alias)
                    else dom_rel_alias end
  
                  debug { "Rel: #{dom_rel} attr: #{dom_attr} orig: #{orig_f}" }
                  debug { "Alias: #{dom_rel_alias} attr: #{dom_attr} orig: #{orig_f}" }
  
                  dom_idx = @schemas[dom_rel].index(dom_rel_alias+dom_attr)
                  
  
                  param = "dom_" + dom_rel_alias + dom_attr
                  if domains.key?(dom_rel) then
                    domains[dom_rel].push(dom_idx)
                  else
                    domains[dom_rel] = [dom_idx]
                  end
                  
                  # Substitute both the LHS and RHS of the constraint for keys
                  key_param_subs[f] = param
                  key_param_subs[orig_f] = param
                  
                  # Substitute only the bound var for constraints
                  pred_var_subs[f] = ":"+param
  
                  # Track param constraints to promote params to group-bys
                  existing_unifiers = param_constraints.fetch(":"+param, [])
                  unifications.concat([existing_unifiers[0] + " = " + norm_orig_f]) if existing_unifiers.length > 0;
                  param_constraints[":"+param] = existing_unifiers.push(norm_orig_f)
  
                  ":"+param
                else f.sub(/__/, ".") end;

              unifications.push([new_f + " = " + norm_orig_f])
            end.flatten.uniq
          
          # Return [relation name, [fields, predicates, domains]]
          [rel_n, fields_and_prefixes.collect { |f,p| f }, predicates, domains]
      end;
      
      # Map params, which should contain only groupby cols, and domain vars.
      map_id = @map_info.select { |k,v| v["map"] == n }.first[0]
      keys = normalize_keys(@templates.select { |t| t.target.source == map_id }.first.target.keys).collect do |k|
          if key_param_subs.key?(k) then key_param_subs[k] else k end
        end

      # Map access patterns
      default_ap = (0...keys.size).to_a.join(",")
      ap = @templates.collect do |t|
          t.access_patterns(map_id).compact.collect do |ap|
            ap.join(".")
          end.uniq.join("|")
        end.uniq.select{|x| (x.length > 0) && !(x == default_ap)}.join("|")

      # Group bys
      params = rels.collect do |x|
        x[3].to_a.collect { |r,i| i.collect { |j| "dom_"+@schemas[r][j] }  }
      end.flatten
      
      group_bys = keys.reject { |k| params.include?(k) }
      
      # Domains (i.e. relations + positions) for map params
      param_sources = rels.collect do |x|
          x[3].to_a.collect { |r,i| i.collect { |j|
            r+"."+(j.to_s)+"=>"+"dom_"+@schemas[r][j] }  }
        end.to_a.select{|x| x.length > 0}.join(",")

      # Substitute params in any constraints in original formula
      subbed_t_preds = t_preds.join(" and ")
      pred_var_subs.each_pair do |s,t|
        subbed_t_preds = subbed_t_preds.gsub(Regexp.quote(s), t)
      end
      
      # Promote params to group-bys if they do not appear in any additional
      # constraints. Note this is very conservative, and params can still be
      # promoted if they appear in equality constraints.
      promoted_params = []
      extra_group_bys = []
      param_constraints.each_pair do |p,v_l|
        debug { "Match #{p}: "+subbed_t_preds.match(p).to_s }
        if subbed_t_preds.match(p).nil? then
          promoted_params.concat(Array.new(v_l.size, p))
          extra_group_bys.concat(v_l)
        end
      end
      
      debug { "Extra group-bys: " + extra_group_bys.join(",") }
      debug { "Promoted params: " + promoted_params.join(",") }
      group_bys.concat(extra_group_bys)

      # Primary map keys
      keys_s = keys.collect do |k|
        if group_bys.include?(k) then "Q."+group_bys.index(k).to_s
        elsif promoted_params.include?(":"+k) then
          "Q."+group_bys.index(extra_group_bys[promoted_params.index(":"+k)]).to_s
        else k end
      end.join(",")

      where_clause = rels.collect do |x|
       x[2].select { |y| not(promoted_params.any? { |gb| y.match(gb) }) }
      end.compact.select { |x| x.length > 0 }.join(" and ");

      # SQL query
      query = 
        "select "+
        (group_bys.length > 0? group_bys.join(",").gsub(/__/,".")+"," : "") +
          "sum("+agg.gsub(/__/,".")+")"+
        " from "+(rels.collect do |x|
          x[0]+(@map_aliases.key?(x[0]) ? " "+@map_aliases[x[0]] : "")
        end.join(", ")) +
        (where_clause.length > 0 || subbed_t_preds.length > 0?
          (" where " + where_clause + subbed_t_preds) : "") +
        (group_bys.length > 0?
          (" group by " + group_bys.join(",").gsub(/__/,".")) : "")

      # Binding vars for parameterized SQL query
      bindvars =
        rels.collect do |x|
          x[3].to_a.collect { |r,i| i.collect { |j| "dom_"+@schemas[r][j] } }
        end.flatten.join(",");

      [n,
        { "param_sources" => param_sources,
          "query" => query,
          "params" => bindvars,
          "keys" => keys_s,
          "aps" => ap
        }]
    end.flatten]
    
    # Add the top-level query
    group_by_match = @query.match(/group *by *([^;]*)/)
    q_group_bys = group_by_match[1].split(",").collect { |gb| gb.strip } unless group_by_match.nil?;
    q_keys_s = []
    q_group_bys.each_index {|i| q_keys_s.push("Q."+i.to_s) } unless q_group_bys.nil?;
    @map_formulae["q"] = {
      "param_sources" => "", "query" => @query, "params" => "",
      "keys" => q_keys_s, "aps" => ""
    } 
  end  
    
  ########################################################
  ## Utility functions
  ########################################################
  
  def template_dag
    @templates.collect do |template|
      [ template.target.source.to_i, template ]
    end.compact.reduce
  end
  
  def map_depth(map)
    @map_info[map].assert_key("depth") do 
      Math.max(@map_info[map]["reads_from"].collect { |read| map_depth(read) }.push(0));
    end
  end
  
  ########################################################
  ## Accessors for the compiled output
  ########################################################
  
  def each_node
    @nodes.each_index do |node_index|
      node = @nodes[node_index];
      partitions = Hash.new { |h, k| h[k] = Array.new };
      @map_info.each_value do |map|
        unless map["discarded"] then
          partitions[map["id"].to_i].push(map["partition"][node_index])
        end
      end
      yield node["name"], partitions, node["address"], (node["port"] || 52982);
    end
  end
  
  def each_template
    @templates.each_index do |i|
      yield i, @templates[i];
    end
  end
  
  def each_map
    @map_info.each_pair do |map, info|
      yield map, info
    end
  end
  
  def success?
    @DBT.nil?
  end
end


#######################
# 
# Wrapper execution

$output = STDOUT;
$boot = nil;
$success = false;
$options = Hash.new;
$toaster_opts = []

# Use home directory as default partition file location, since this is also
# the default for the source directive.
$pfile_basepath = "~"

$toaster = DBToaster.new()

opts = GetoptLong.new(
  [ "-o", "--output",            GetoptLong::REQUIRED_ARGUMENT ],
  [       "--node",              GetoptLong::REQUIRED_ARGUMENT ],
  [       "--switch",            GetoptLong::REQUIRED_ARGUMENT ],
  [       "--switch-forwarders", GetoptLong::REQUIRED_ARGUMENT ],
  [       "--switch-tree",       GetoptLong::REQUIRED_ARGUMENT ],
  [       "--partition",         GetoptLong::REQUIRED_ARGUMENT ],
  [       "--domain",            GetoptLong::REQUIRED_ARGUMENT ],
  [       "--test",              GetoptLong::REQUIRED_ARGUMENT ],
  [       "--slice",             GetoptLong::REQUIRED_ARGUMENT ],
  [       "--key",               GetoptLong::REQUIRED_ARGUMENT ],
  [ "-r", "--transforms",        GetoptLong::REQUIRED_ARGUMENT ],
  [       "--persist",           GetoptLong::NO_ARGUMENT ],
  [ "-k", "--ignore-keys",       GetoptLong::NO_ARGUMENT ],
  [ "-w", "--switch-addr",       GetoptLong::REQUIRED_ARGUMENT ],
  [ "-b", "--boot",              GetoptLong::REQUIRED_ARGUMENT ],
  [ "-p", "--pfile",             GetoptLong::REQUIRED_ARGUMENT ]
).each do |opt, arg| 
  case opt
    when "-o", "--output"          then $output = File.open(arg, "w+"); at_exit { File.delete(arg) unless $toaster.success? && $success };
    when "-k", "--ignore-keys"     then $options[:toast_keys] = false;
    when "-b", "--boot"            then $boot = File.open(arg, "w+"); at_exit { File.delete(arg) unless $toaster.success? && $success };
    when "-p", "--pfile"           then $pfile_basepath = arg;
    else                            $toaster_opts.push([opt, arg])
  end
end

$toaster_opts.each { |oa| opt, arg = oa; $toaster.parse_arg(opt, arg) }

ARGV.each do |f|
  $toaster.load(File.open(f).readlines);
end

$toaster.toast($options);


CLog.debug { "=========  Maps  ===========" }
$toaster.map_info.each_value do |info|
  CLog.debug { info["map"].to_s + "(" + info["id"].to_s + ")" + " : " + info["num_keys"].to_s + " keys" unless info["discarded"]; }
end

map_keys = Hash.new;
$output.write("\n\n############ Put Templates\n");
$toaster.each_template do |i, template|
  $output.write("template " + (i+1).to_s + " " + template.to_s + "\n");
  map_keys.assert_key(template.target.source) { template.target.keys };
end

#$output.write("\n\n############ Map Information\n");
#$toaster.each_map do |map, info|
#  $output.write("map " + map.to_s + " => Depth " + info["depth"].to_s + ";");
#end

CLog.debug { "========== Map definitions ===========" }
$toaster.map_info.each_value do |info|
  n = info["map"].to_s
  if $toaster.map_formulae.key?(n) then
    boot_spec = $toaster.map_formulae[n]

    last_node_partition = info["partition"][info["partition"].size-1]
    partition_keys = []
    last_node_partition.each_index do |i|
      if last_node_partition[i] != 0 then partition_keys.push(i) end
    end
  
    partition_sizes = partition_keys.collect do |i|
      info["partition"][info["partition"].size-1][i]+1
    end
  
    #node_partitions = info["partition"].collect do |np|
    #  partition_keys.collect { |i| np[i] }.join(".")
    #end

    boot_spec_s = [ "param_sources", "query", "params", "keys"].collect do |k|
      boot_spec[k]
    end.join("\n")+(boot_spec["aps"].length > 0? ("/"+boot_spec["aps"]) : "");

    p = [ partition_keys.join(","), partition_sizes.join(",") ].join("/")
    map_def = [n, boot_spec_s, p].join("\n")
    
    CLog.debug { map_def }
    $boot.write(map_def+"\n") if $boot;
  end
end

$boot.flush if $boot;

CLog.info { "==== Partition Choices =====" }

$toaster.map_info.each_value do |info|
  unless info["discarded"] then
    CLog.info { info["map"].to_s + "(" + info["id"].to_s + ")" }
    info["partition"][info["partition"].size-1].each_with_index do |c,i| 
      CLog.info { "    " + map_keys[info["id"]][i].to_s + " (" + i.to_s + "): " + (c.to_i + 1).to_s }
    end
  end
end

$output.write("\n\n############ Node Definitions\n");
first_node = true;
$output.write("switch " + $toaster.switch+"\n");
if $toaster.switch_tree.size == 2 then
  $output.write("switch_tree " +($toaster.switch_tree.collect{ |i| i.to_i }.join(","))+"\n")
else
  $output.write("switch_forwarders " + $toaster.switch_forwarders.to_s+"\n");
end

$toaster.each_node do |node, partitions, address, port|
  $output.write("node " + node.to_s + "\n");
  $output.write("address " + address.to_s + ":" + port.to_s + "\n");
  partitions.each_pair do |map, plist|
    plist.each_index do |pidx|
      segment = plist[pidx]
      map_segment = map.to_s + "[" + segment.join(",") + "]"
      map_name = $toaster.map_info[map]["map"].to_s
      node_id = $toaster.map_info[map]["partition"].index(segment)

      $output.write("partition Map " + map_segment + "\n");
    end
  end
end

$output.write("\n\n############ Test Sequence\n");
$output.write($toaster.test_directives.collect do |l| "update " + l end.join("\n")+"\n");
$output.write("persist\n") if $toaster.persist;

unless $toaster.slice_directives.empty? then
  $output.write("\n\n############ Slicer Debugging Directives\n");
  $output.write($toaster.slice_directives.join("\n") + "\n");
end

$output.flush;

$success = true;
