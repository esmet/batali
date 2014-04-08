require 'rubygems'
require 'bundler/setup'

require 'fog'
require 'json'
require 'ostruct'
require 'pmap'
require 'ridley'

require_relative 'batali/server.rb'

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

    # @param [hash] hash
    # @return [hash] deep copy of `hash'
    private
    def deeply_copy_hash(hash)
      Marshal.load(Marshal.dump(hash))
    end

    # Cook up a cluster using the given options. I should document them soon.
    # Nodes are named by the role they are performing. If there's a node named
    # foobar, it's Chef role is foobar.
    public
    def cook(options = {})
      puts "batali: cooking up cluster #{options.cluster}"
      cluster = Cluster.new(options, @config)

      base_attributes = JSON.parse(
        File.read(File.expand_path('../batali/json/tokumx_base.json', __FILE__)),
        symbolize_names: true
      ).to_hash
      base_attributes[:mongodb][:cluster_name] = options.cluster
      base_recipes = [ "apt", "tokumx::tokutek_repo" ]
      base_node_name = "#{base_attributes[:mongodb][:cluster_name]}"

      # Bootstrap the config servers and shards in parallel, since they do not
      # depend on each other or on the state of the Chef server. Once they
      # are done, bootstrap the mongos routers, which use Chef server state
      # to tie everything together.

      # config servers / shards
      bootstrap_args = []
      options.config_servers.times do |i|
        name = "#{base_node_name}_config#{i}"
        bootstrap_args << [ name, base_recipes + ['mongodb::configserver'], base_attributes ]
      end
      options.shards.times do |shard_num|
        options.rs_members.times do |rs_num|
          name = "#{base_node_name}_shard#{shard_num}_rs#{rs_num}"
          shard_attributes = deeply_copy_hash(base_attributes)
          shard_attributes[:mongodb][:config][:expireOplogDays] = 1
          shard_attributes[:mongodb][:config][:slowms] = 1000
          shard_attributes[:mongodb][:config][:replSet] = "rs_shard#{shard_num}"
          shard_attributes[:mongodb][:shard_name] = "shard#{shard_num}"
          bootstrap_args << [ name, base_recipes + ['mongodb::replicaset', 'mongodb::shard'], shard_attributes ]
        end
      end
      bootstrap_args.pmap { |name, recipe, attributes| cluster.spinup(name, recipe, attributes) }

      # mongos routers 
      bootstrap_args = []
      options.mongos_routers.times do |i|
        name = "#{base_node_name}_mongos#{i}"
        mongos_attributes = deeply_copy_hash(base_attributes)
        # mongos does not appreciate being passed the dbpath option
        mongos_attributes[:mongodb][:config].delete(:dbpath)
        bootstrap_args << [ name, base_recipes + ['mongodb::mongos'], mongos_attributes ]
      end
      bootstrap_args.pmap { |name, recipe, attributes| cluster.spinup(name, recipe, attributes) }

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
