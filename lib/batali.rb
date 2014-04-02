require 'ostruct'
require 'optparse'
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
      self
    end

    def cook(options = {})
      puts "Batali is cooking up a cluster given the following options: #{options.inspect}"

      # Create roles for each config server, shard, and mongos router.

      options.config_servers.times do |config_server_num|
        puts "Creating role for config server #{config_server_num}"
      end

      options.shards.times do |shard_num|
        options.rs_members.times do |rs_member_num|
          puts "Creating role for shard #{shard_num}, member #{rs_member_num}"
        end
      end

      options.mongos_routers.times do |mongos_num|
        puts "Creating role for mongos #{mongos_num}"
      end

      # Cook up each server, starting with the config servers, then each shard's replica set members,
      # then the mongos routers. The routers come last because the mongos Chef recipe joins all
      # shards with the same cluster name to the cluster.

      options.config_servers.times do |config_server_num|
        puts "Cooking up config server #{config_server_num}"
      end

      options.shards.times do |shard_num|
        options.rs_members.times do |rs_member_num|
          puts "Cooking up shard #{shard_num}, member #{rs_member_num}"
        end
      end

      options.mongos_routers.times do |mongos_num|
        puts "Cooking up mongos #{mongos_num}"
      end
    end
  end

end
