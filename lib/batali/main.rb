require 'ostruct'
require 'optparse'
require_relative '../batali.rb' # TODO: This almost certainly can be cleaner

options = {}
OptionParser.new do |parser|
  options = OpenStruct.new
  options.verbose = false
  options.knife_config_file = '.batali/knife.rb'
  options.config_servers = 1
  options.shards = 1
  options.rs_members = 1
  options.mongos_routers = 1
  options.cluster = 'batali_default'
  options.teardown = false
  options.dry = false

  parser.banner = "Usage: batali.rb [options]"

  parser.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options.verbose = v
  end

  parser.on("-f", "--knife-config-file <path>", String, "Path to a knife.rb config file to use") do |path|
    options.knife_config_file = path
  end

  parser.on("--config-servers N", Integer, "Number of config servers to deploy") do |n|
    options.config_servers = n
  end

  parser.on("--mongos-routers N", Integer, "Number of mongos routers to deploy") do |n|
    options.mongos_routers = n
  end

  parser.on("--shards N", Integer, "Number of shards to deploy") do |n|
    options.shards = n
  end

  parser.on("--rs-members N", Integer, "Number of replica set members per shard") do |n|
    options.rs_members = n
  end

  parser.on("--cluster <name>", String, "The name of the cluster that Batali will operate on") do |name|
    options.cluster = name
  end

  parser.on("--[no-]teardown", "Whether to teardown the cluster provided by --cluster") do |teardown|
    options.teardown = teardown
  end

  parser.on("--[no-]dry", "Whether to perform a dry run (print the steps, don't actually do them)") do |dry|
    options.dry = dry
  end
end.parse!

puts "main: running with options #{options.inspect}" if options.verbose

batali = Batali.new(options)
if options.teardown
  batali.teardown(options)
else
  batali.cook(options)
end

puts "main: done" if options.verbose
