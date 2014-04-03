require 'fog'
require 'json'
require 'ostruct'
require 'optparse'
require 'pmap'
require 'ridley'

module Batali

  class << self
    def new(options = {})
      Ridley::Logging.logger.level = Logger.const_get 'ERROR' unless options.verbose

      # TODO SSL should be an option. Once it is, we can use the from_config_file
      #      constructor, which seems to not properly accept ssl.verify = false
      config = Ridley::Chef::Config.new(options.knife_config_file).to_hash
      config[:validator_client] = config.delete(:validation_client_name)
      config[:validator_path]   = config.delete(:validation_key)
      config[:client_name]      = config.delete(:node_name)
      config[:server_url]       = config.delete(:chef_server_url)
      config[:ssl]              = { verify: false }

      @ridley = Ridley.new(config)
      @ridley.environment.all # quick check to see that our connection is ok
      @aws = Fog::Compute.new(
        provider: 'AWS',
        aws_access_key_id: config[:knife][:aws_access_key_id],
        aws_secret_access_key: config[:knife][:aws_secret_access_key],
        region: config[:knife][:aws_region] || "us-east-1d"
      )
      @all_aws_servers = Hash[@aws.servers.all.collect { |server| [ server.tags["Name"].to_s, server ] }]

      self
    end


    # Provisions a chef server to assume the given role, if no instance is
    # currently online for that role.
    # @param [hash] role
    private
    def provision_instance_with_role(role)
      puts "Provisioning instance for role #{role[:name]}"
      @ridley.role.delete(role[:name])
      @ridley.role.create(role)
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
      role_base_hash = JSON.parse(
        File.read(File.expand_path('../batali/json/role_base.json', __FILE__)),
        symbolize_names: true
      ).to_hash

      # node names look like cluster_name + flavor + num
      # eg: cluster0_mongos0, mycluster_shard5
      role_base_hash[:override_attributes][:mongodb][:cluster_name] = options.cluster
      node_name = lambda do |flavor, n|
        "#{role_base_hash[:override_attributes][:mongodb][:cluster_name]}_#{flavor}#{n}"
      end

      # lambdas for generating role hashes
      configserver_role = lambda do |configserver_num|
        role = deeply_copy_hash(role_base_hash)
        role[:name] = node_name.call('configserver', configserver_num)
        role[:run_list] << "recipe[mongodb::configserver]"
        role
      end
      shard_role = lambda do |shard_num|
        role = deeply_copy_hash(role_base_hash)
        shard_name = "shard#{shard_num}"
        rs_name = "rs_#{shard_name}"
        role[:name] = node_name.call('shard', shard_num)
        role[:run_list] << "recipe[mongodb::replicaset]"
        role[:run_list] << "recipe[mongodb::shard]"
        role[:override_attributes][:mongodb][:config][:expireOplogDays] = 1
        role[:override_attributes][:mongodb][:config][:slowms] = 1000
        role[:override_attributes][:mongodb][:config][:replSet] = "rs_shard#{shard_num}"
        role[:override_attributes][:mongodb][:shard_name] = "shard#{shard_num}"
        role
      end
      mongos_role = lambda do |mongos_num|
        role = deeply_copy_hash(role_base_hash)
        role[:name] = node_name.call('mongos', mongos_num)
        role[:run_list] << "recipe[mongodb::mongos]"
        role
      end

      # Create an array of roles, consisting of the roles for config servers, shards
      # and mongos routers, then provisional them all in parallel using pmap, but save
      # the last mongos router for last.
      (Array.new(options.config_servers) do |i|
        configserver_role.call(i)
      end + Array.new(options.shards) do |i|
        shard_role.call(i)
      end + Array.new((options.mongos_routers - 1) || 1) do |i|
        next if i == options.mongos_routers - 1
        mongos_role.call(i)
      end).pmap { |role| provision_instance_with_role(role) }

      # Once we know all of the config servers and shards are online, we can
      # provision the last mongos router, which ties everything together.
      provision_instance_with_role(mongos_role.call(options.mongos_routers - 1))
    end
  end

end
