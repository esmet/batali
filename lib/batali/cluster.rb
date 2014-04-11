require 'fog'
require 'ostruct'
require 'pmap'

module Batali
  class Cluster
    def initialize(options, config)
      @options = options
      @config = config
      @cluster_name = options.cluster
      raise "Cluster needs a name" if @cluster_name.nil?

      # TODO: Verify that config
      #       - aws_identity_file
      #       - aws_access_key_id
      #       - aws_secret_access_key
      #       - others?
      @aws = Fog::Compute.new(
        provider:               'AWS',
        aws_access_key_id:      @config[:knife][:aws_access_key_id],
        aws_secret_access_key:  @config[:knife][:aws_secret_access_key],
        region:                 @config[:knife][:region] || "us-east-1",
      )
    end

    public
    def all_servers
      servers = @aws.servers.all.collect do |server|
        name = server.tags["Name"].to_s
        if name.match(/^#{@cluster_name}/) && server.key_name == "esmet"
           (server.state == "running" || server.state == "pending") &&
          [ name, server ] 
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
    def knife_ec2_server_create(name, recipes, attributes)
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
      ]

      cmd = knife_cmd * ' '
      if @options.dry
        puts "dry run: #{cmd}"
        return true
      end

      system(cmd)
    end

    public
    def spinup(name, recipes, attributes)
      raise "A server named #{name} already exists" if all_servers[name]
      knife_ec2_server_create(name, recipes, attributes)
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

      system(cmd)
    end

    # Teardown the entire cluster
    public
    def teardown()
      n = all_servers.size
      all_servers.each_slice(8).to_a.each do |slice|
        slice.peach do |name, server| 
          ok = knife_ec2_server_delete(name, server.id)
          raise "teardown failed to delete server #{name}" if !ok
        end
      end
      n
    end
  end
end
