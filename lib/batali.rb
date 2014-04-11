require 'rubygems'
require 'bundler/setup'

require 'pmap'
require 'ridley'

require_relative 'batali/chef.rb'
require_relative 'batali/cluster.rb'
require_relative 'batali/node.rb'

module Batali
  class << self
    # TODO Document options
    def new(options)
      @chef = Chef.new options
      # check that required cookbooks are available through Chef
      cookbooks = @chef.cookbooks
      ['apt', 'mongodb', 'tokumx'].each do |name|
        if cookbooks[name].nil?
          raise "#{name}: cookbook not found on chef server, please upload it"
        end
      end
      @config = @chef.config
      self
    end

    private
    def spinup_node(cluster, node)
      ok = cluster.spinup(cluster, node.name, node.recipes, node.attributes)
      raise if !ok
    end

    # Cook up a cluster using the given options. I should document them soon.
    # Nodes are named by the role they are performing. If there's a node named
    # foobar, it's Chef role is foobar.
    public
    def cook(options)
      cluster = Cluster.new(options, @config)

      # Bootstrap the config servers and shards in parallel, since they do not
      # depend on each other or on the state of the Chef server. Once they
      # are done, bootstrap the mongos routers, which use Chef server state
      # to tie everything together.

      existing_servers = cluster.all_servers

      # config servers / shards
      nodes_to_spinup = []
      options.config_servers.times do |i|
        node = Node::ConfigServer.new(options, i)
        nodes_to_spinup << node if existing_servers[node.name].nil?
      end
      options.shards.times do |shard_num|
        options.rs_members.times do |rs_num|
          node = Node::Shard.new(options, shard_num, rs_num)
          nodes_to_spinup << node if existing_servers[node.name].nil?
        end
      end
      nodes_to_spinup.each_slice(8).to_a.each { |slice| slice.pmap { |node| spinup_node(cluster, node ) } }

      # mongos routers 
      nodes_to_spinup = []
      options.mongos_routers.times do |i|
        node = Node::Mongos.new(options, i)
        nodes_to_spinup << node if existing_servers[node.name].nil?
      end
      nodes_to_spinup.each_slice(8).to_a.each { |slice| slice.pmap { |node| spinup_node(cluster, node) } }
    end

    public
    def teardown(options)
      cluster = Cluster.new(options, @config)
      cluster.teardown
    end

    public
    def show(options)
      cluster = Cluster.new(options, @config)
      servers = cluster.all_servers.collect { |name, server| [ name, server.dns_name ] }
      Hash[servers]
    end
  end
end
