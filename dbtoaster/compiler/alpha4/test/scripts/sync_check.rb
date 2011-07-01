#!/usr/bin/env ruby
require 'test/scripts/util.rb'
require 'tempfile'

script = ARGV[0];
script_data = File.open(script).readlines;

$tables = Hash.new { |h,k| h[k] = Hash.new(0) };

$pg_script =
  script_data.
    map {|i| i.sub(/--.*/, "")}.
    map {|i| i.chomp }.join(" ").
    sub(/\/\*.*\*\//, "").
    split(/ *; */).
    map do |cmd| 
      case cmd 
        when /CREATE TABLE ([^(]+)\(([^)]*)/ then 
          $tables[$1.downcase];
          "CREATE TEMPORARY TABLE #{$1.downcase}(#{$2});\n"+
          "COPY #{$1} FROM '@@#{$1.downcase}@@' DELIMITER ',';"
        when /SELECT */ then "#{cmd};"
        else "xxx"
      end
    end.
    join("\n");

dbt_cmd = 
  "./dbtoaster -r -d step-interpreter -d log-interpreter-updates #{script}";

def update_rel(op, rel, key)
  rel = rel.downcase;
  if op == "-" then
    if $tables[rel][key] = 1 then $tables[rel].delete(key)
    elsif $tables[rel][key] < 1 then puts "ERROR: invalid delete"; exit -1;
    else $tables[rel][key] = $tables[rel][key] - 1;
    end
  else
    $tables[rel][key] = $tables[rel][key] + 1;
  end
end

def compare_results(dbtoaster, postgres = correct_results)
  (dbtoaster.keys + postgres.keys).uniq.each do |k|
    if dbtoaster[k].to_f != postgres[k].to_f then
      puts "============ Value Mismatch ============";
      puts "--- STATE ---";
      p $tables;
      puts "--- Key/EXPECTED/DBToaster ---";
      puts (
        (dbtoaster.keys + postgres.keys).uniq.map do |k| 
          "[#{k.join(", ")}] / #{postgres[k]} / #{dbtoaster[k]}"
        end.join("\n");
      );
      exit -1;
    end
  end
end

def correct_results()
  pg_script = $pg_script;
  rel_files = $tables.map do |rname, vals|
    f = Tempfile.new(rname)
    vals.each do |row,arity|
      (0...arity).each { f.puts(row.join(",")) };
    end
    f.flush
    pg_script = pg_script.sub("@@#{rname.downcase}@@", f.path);
    f
  end
  correct = 
    IO.popen("psql dbtoaster -t", "r+") do |psql|
      psql.puts(pg_script);
      psql.close_write;
      results = psql.readlines
#      p results;
      results.
        delete_if { |row| not (row.include? "|") }.
        map do |row| 
          row.chomp.split(/ *\| */).map { |i| i.to_f }
        end.
        delete_if { |i| i == ""; }.
        map { |row| [(k = row.clone), (k.pop)] }.
        to_h
    end
  rel_files.each { |f| f.close! }
  correct;
end


IO.popen(dbt_cmd, "r+") do |f|
  loop do
    line = f.gets;
    puts line;
    case line
      when /^(\+|-)([a-zA-Z]+)\[([\-0-9.; ]*)\]/ then 
        update_rel($1, $2, $3.split(/; */).map {|i| i.to_f});
        
      when /^\[QUERY_1_1->(\[?[^<]*)<pat=/ then
        results = 
          $1.split(/; *\[/).map do |entry| 
            if (/([\-0-9.; ]*)\]->(-?[0-9.]+)/ =~ entry) then
              [ $1, $2 ]
            else
              nil
            end
          end.
            delete_if { |i| i.nil? }.
            map {|k,v| [k.split(/; */).map {|i| i.to_f}, v.to_f]}.
            to_h
        compare_results(results)
        f.puts "\n";
    end
  end
end