require 'json'

module Batali
  class Node
    attr_reader :name, :recipes, :attributes

    # setup attributes and recipes common to all nodes.
    def initialize(options)
      raise if options.cluster.nil? || options.cluster.empty?

      @name = options.cluster
      @recipes = [ 'apt', 'tokumx::tokutek_repo' ]
      @attributes = JSON.parse(
        # TODO: Make this nicer
        File.read(File.expand_path('../../batali/json/tokumx_base.json', __FILE__)),
        symbolize_names: true
      ).to_hash
      @attributes[:mongodb][:cluster_name] = options.cluster
    end

    # @param [hash] hash
    # @return [hash] deep copy of `hash'
    private
    def deeply_copy_hash(hash)
      Marshal.load(Marshal.dump(hash))
    end

    class ConfigServer < Node
      def initialize(options, configserver_num = 0)
        super(options)
        @name += "_configserver#{configserver_num}"
        @recipes += [ 'mongodb::configserver', 'mongodb::shard' ]
      end
    end

    class Shard < Node
      def initialize(options, shard_num = 0, rs_num = 0)
        super(options)
        @name += "_shard#{shard_num}_rs#{rs_num}"
        @recipes += [ 'mongodb::replicaset', 'mongodb::shard' ]
        shard_attributes = deeply_copy_hash(@attributes)
        shard_attributes[:mongodb][:config][:expireOplogDays] = 1
        shard_attributes[:mongodb][:config][:slowms] = 1000
        shard_attributes[:mongodb][:config][:replSet] = "rs_shard#{shard_num}"
        shard_attributes[:mongodb][:shard_name] = "shard#{shard_num}"
        @attributes = shard_attributes
      end
    end

    class Mongos < Node
      def initialize(options, which = 0)
        super(options)
        @name += "_mongos#{which}"
        @recipes += [ 'mongodb::mongos' ]

        # mongos does not appreciate the dbpath parameter
        mongos_attributes = deeply_copy_hash(@attributes)
        mongos_attributes[:mongodb][:config].delete(:dbpath)
        @attributes = mongos_attributes
      end
    end

  end
end
