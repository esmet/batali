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
    def spinup_nodes(cluster, nodes)
      nodes.each do |node|
        ok = cluster.spinup(cluster.name, node.name, node.recipes, node.attributes)
        raise if !ok
      end
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

      spinup_slice = 4 # run no more than spinup 4 jobs in parallel
      existing_servers = cluster.servers

      # config servers / shards
      node_sets = []
      options.config_servers.times do |i|
        node = Node::ConfigServer.new(options, i)
        node_sets << [ node ] if existing_servers[node.name].nil?
      end
      options.shards.times do |shard_num|
        rs_set = []
        options.rs_members.times do |rs_num|
          node = Node::Shard.new(options, shard_num, rs_num)
          rs_set << node if existing_servers[node.name].nil?
        end
        node_sets << rs_set
      end
      node_sets.each_slice(spinup_slice).to_a.each { |slice| slice.pmap { |nodes| spinup_nodes(cluster, nodes ) } }

      # mongos routers 
      mongos_routers = []
      options.mongos_routers.times do |i|
        node = Node::Mongos.new(options, i)
        mongos_routers << [ node ] if existing_servers[node.name].nil?
      end
      mongos_routers.each_slice(spinup_slice).to_a.each { |slice| slice.pmap { |nodes| spinup_nodes(cluster, nodes) } }
    end

    public
    def teardown(options)
      cluster = Cluster.new(options, @config)
      cluster.teardown
    end

    public
    def show(options)
      cluster = Cluster.new(options, @config)
      servers = cluster.servers.collect do |name, server|
        info = { flavor: server.flavor_id, url: server.dns_name }
        [ name, info ]
      end
      Hash[servers]
    end

    public
    def clusters
      Cluster::clusters(@config)
    end
  end
end
