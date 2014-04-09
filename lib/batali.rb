require 'rubygems'
require 'bundler/setup'

require 'pmap'
require 'ridley'

require_relative 'batali/node.rb'
require_relative 'batali/cluster.rb'

module Batali

  class << self
    # TODO Document options
    def new(options)
      Ridley::Logging.logger.level = Logger.const_get 'ERROR'

      # TODO SSL should be an option. Once it is, we can use the from_config_file
      #      constructor, which seems to not properly accept ssl.verify = false
      config = Ridley::Chef::Config.new(options.knife_config_file).to_hash
      config[:validator_client] = config.delete(:validation_client_name)
      config[:validator_path]   = config.delete(:validation_key)
      config[:client_name]      = config.delete(:node_name)
      config[:server_url]       = config.delete(:chef_server_url)
      config[:ssl]              = { verify: false }
      config[:ssh]              = { user: 'ubuntu', keys: config[:knife][:aws_identity_file] }
      @config = config

      @ridley = Ridley.new(@config)
      cookbooks = Hash[@ridley.cookbook.all.collect { |cookbook| [ cookbook[0], cookbook[1] ] }]
      ['apt', 'mongodb', 'tokumx'].each do |name|
        print "checking for cookbook #{name}... "
        if cookbooks[name].nil?
          puts "not found. please ensure that it is uploaded to the Chef server."
          raise
        else
          puts "ok"
        end
      end

      self
    end

    # Cook up a cluster using the given options. I should document them soon.
    # Nodes are named by the role they are performing. If there's a node named
    # foobar, it's Chef role is foobar.
    public
    def cook(options = {})
      puts "batali: cooking up cluster #{options.cluster}"
      cluster = Cluster.new(options, @config)

      # Bootstrap the config servers and shards in parallel, since they do not
      # depend on each other or on the state of the Chef server. Once they
      # are done, bootstrap the mongos routers, which use Chef server state
      # to tie everything together.

      # config servers / shards
      nodes_to_spinup = []
      options.config_servers.times do |i|
        nodes_to_spinup << Node::ConfigServer.new(options, i)
      end
      options.shards.times do |shard_num|
        options.rs_members.times do |rs_num|
          nodes_to_spinup << Node::Shard.new(options, shard_num, rs_num)
        end
      end
      nodes_to_spinup.pmap { |node| cluster.spinup(node.name, node.recipes, node.attributes) }

      # mongos routers 
      nodes_to_spinup = []
      options.mongos_routers.times do |i|
        nodes_to_spinup << Node::Mongos.new(options, i)
      end
      nodes_to_spinup.pmap { |node| cluster.spinup(node.name, node.recipes, node.attributes) }

      puts "batali: note: you may need to ssh into mongos and do 'sudo chef-client' to properly join all shards"
      puts "batali: done"
    end

    public
    def teardown(options = {})
      puts "batali: tearing down cluster #{options.cluster}"
      cluster = Cluster.new(options, @config)
      cluster.teardown
      puts "batali: done"
    end
  end
end
