require 'fog'
require 'ostruct'
require 'pmap'
require 'open3'

module Batali
  class Cluster
    attr_reader :name

    private
    def self.aws(config)
      # TODO: Verify that config
      #       - aws_identity_file
      #       - aws_access_key_id
      #       - aws_secret_access_key
      #       - others?
      Fog::Compute.new(
        provider:               'AWS',
        aws_access_key_id:      config[:knife][:aws_access_key_id],
        aws_secret_access_key:  config[:knife][:aws_secret_access_key],
        region:                 config[:knife][:region] || "us-east-1",
      )
    end

    def initialize(options, config)
      raise "Cluster needs a valid name in options.cluster" if (options.cluster || '') == ''
      @name = options.cluster
      @options = options
      @config = config
      @aws = self.class.aws(config)
    end

    # @return true if the given server found on aws is ok for Batali to use
    private
    def self.server_ok_to_use(server)
      # only use servers created by "esmet" that are in the running or pending state
      server.key_name == "esmet" && (server.state == "running" || server.state == "pending")
    end

    # TODO Passing the config here is poor design.
    #
    # @param config, the knife/batali config (aws key id / access key / etc) 
    # @return Set (String) all cluster names that Batali knows about
    def self.clusters(config)
      clusters = Hash.new
      aws(config).servers.all.each do |server|
        cluster_tag = server.tags["BataliCluster"].to_s
        if server_ok_to_use(server) && cluster_tag != ''
          if clusters[cluster_tag].nil?
            clusters[cluster_tag] = Hash.new
          end
          clusters[cluster_tag][server.tags["Name"].to_s] = server
        end
      end
      clusters
    end

    # @return Hash (server name, server) of all servers running in this cluster
    public
    def servers
      servers = @aws.servers.all.collect do |server|
        if self.class.server_ok_to_use(server) &&
           server.tags["BataliCluster"].to_s == @name
          [ server.tags["Name"].to_s, server ]
        end
      end.compact
      Hash[servers]
    end

    # Use the knife-ec2 command line tool to create a server, running
    # the given recipes and setting the given attributes during bootstrap.
    #
    # @param name [String] name of the server to create - if none exists it will be provisioned
    # @param recipes [Array] recipes to run
    # @param attributes [Hash] attributes to use during bootstrap
    private
    def knife_ec2_server_create(cluster, name, recipes, attributes)
      puts "knife ec2 server create: name #{name}"
      identity_file = @config[:knife][:aws_identity_file]
      run_list = recipes.map{ |recipe| "recipe[#{recipe}]" } * ","
      json_attributes_s = attributes.to_json.to_s
      knife_cmd = [
        'knife',              "ec2 server create",
        '--config',           ".batali/knife.rb",
        '--identity-file',    "\'#{identity_file}\'",
        '--node-name',        "\'#{name}\'",
        '--ssh-user',         "ubuntu",
        '--run-list',         "\'#{run_list}\'",
        '--json-attributes',  "\'#{json_attributes_s}\'",
        '--tags',             "BataliCluster=\'#{cluster}\'",
      ]

      cmd = knife_cmd * ' '
      if @options.dry
        puts "dry run: #{cmd}"
        return true
      end

      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        while line = stdout.gets
          puts line
        end

        exit_status = wait_thr.value
        unless exit_status.success?
          puts "warning: knife cmd '#{cmd}' failed!"
        end
      end
    end

    public
    def spinup(cluster, name, recipes, attributes)
      raise "A server named #{name} already exists in cluster #{cluster}" if servers[name]
      knife_ec2_server_create(cluster, name, recipes, attributes)
    end

    # Use the knife-ec2 command line tool because wrangling with fog
    # plus ridley bootstrap is hard to get right.
    #
    # @param name [String] name of the server to delete
    # @param instance_id [String] ec2 instance id (sometimes looks like i-12345678)
    private
    def knife_ec2_server_delete(name, instance_id)
      puts "-- knife ec2 delete: #{name}, instance_id #{instance_id}"
      knife_cmd = [
        'knife',       "ec2 server delete",
        '--config',    ".batali/knife.rb",
        '--node-name', "\'#{name}\'",
        '--purge',
        '--yes',
        "\'#{instance_id}\'"
      ]

      cmd = knife_cmd * ' '
      if @options.dry
        puts "dry run: #{cmd}"
        return true
      end

      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        while line = stdout.gets
          puts line
        end

        exit_status = wait_thr.value
        unless exit_status.success?
          puts "warning: knife cmd '#{cmd}' failed!"
        end
      end
    end

    # Teardown the entire cluster
    public
    def teardown()
      n = servers.size
      servers.each_slice(4).to_a.each do |slice|
        slice.peach do |name, server| 
          ok = knife_ec2_server_delete(name, server.id)
          raise "teardown failed to delete server #{name}" if !ok
        end
      end
      n
    end
  end
end
