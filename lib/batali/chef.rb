require 'ridley'

module Batali
  class Chef
    # TODO: This won't be necessary once option/config passing is sane
    attr_reader :config

    def initialize(options)
      raise "Need options and the knife_config_file field" if !options or options.knife_config_file.nil?
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
    end

    public
    def cookbooks
      cookbooks = @ridley.cookbook.all.collect { |cookbook| [ cookbook[0], cookbook[1] ] }
      Hash[cookbooks]
    end
  end
end
