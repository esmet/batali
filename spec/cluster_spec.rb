require 'ostruct'

require_relative '../lib/batali/cluster.rb'

class AwsServerMock
  attr_reader :tags, :state, :key_name, :id
  def initialize cluster, server_name, state, key_name
    @tags = { "Name" => server_name, "BataliCluster" => cluster }
    @state = state
    @key_name = key_name
    @id = "mockid-#{server_name}_#{key_name}"
  end
end

class FogComputeMock
  attr_reader :servers
  def initialize all_mocked_servers = []
    @servers = OpenStruct.new({ all: all_mocked_servers })
  end
end

include Batali

describe Cluster do
  let :test_cluster_name do
    ':test_cluster_name'
  end
  let :test_options do
    OpenStruct.new({ cluster: test_cluster_name })
  end
  let :test_config do
    {
      knife: {
        provider: 'AWS',
        aws_access_key_id: 'key_id',
        aws_secret_access_key: 'access_key',
        region: 'region'
      }
    }
  end

  describe "#new" do
    let :test_servers do
      [ AwsServerMock.new('cluster_name', 'server', 'state', 'key_name') ]
    end
    let :test_fog_compute_mock do
      FogComputeMock.new test_servers
    end

    before :each do
      # stub the Fog dependency
      Fog::Compute.stub(:new) { test_fog_compute_mock }
      @cluster = Cluster.new test_options, test_config
    end

    it "creates a new Cluster object" do
      @cluster.should be_an_instance_of Cluster
    end
    
    it "raises an error when cluster is missing from the options parameter" do
      expect { Cluster.new OpenStruct.new, test_config } .to raise_error
    end
    
    it "raises an error when cluster is the empty string" do
      expect { Cluster.new OpenStruct.new(cluster: ''), test_config } .to raise_error
    end

    it "sets the options, config, and cluster_name fields properly" do
      @cluster.instance_variable_get(:@options).should eql test_options
      @cluster.instance_variable_get(:@config).should eql test_config
    end

    it "creates an instance of Fog::Compute and stores it in @aws" do
      @cluster.instance_variable_get(:@aws).should eql test_fog_compute_mock
    end
  end

  describe "#name" do
    it "returns the name of the cluster provided by the options to #new" do
      Fog::Compute.stub(:new) { FogComputeMock.new [] }
      cluster = Cluster.new test_options, test_config
      expect(cluster.name).to be(test_options.cluster)
    end
  end

  describe "#clusters" do
    it "returns a Hash mapping cluster name to some data" do
      sample_servers = [
        AwsServerMock.new('cluster0', "cluster0_server0", 'running', 'esmet'),
        AwsServerMock.new('cluster1', "cluster1_server1", 'running', 'esmet'),
        AwsServerMock.new('cluster1', "cluster1_server2", 'running', 'esmet'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      clusters = Cluster.clusters(test_config);
      expect(clusters).to be_an_instance_of(Hash)
      expect(clusters.size).to eql 2
      expect(clusters.keys).to eql ['cluster0', 'cluster1']
    end

    it "returns nothing if there are no servers" do
      Fog::Compute.stub(:new) { FogComputeMock.new [] }
      expect(Cluster.clusters(test_config)).to eql Hash.new
    end

    it "returns a cluster if at least one member is running" do
      sample_servers = [
        AwsServerMock.new('cluster0', "cluster0_server0", 'running', 'esmet'),
        AwsServerMock.new('cluster0', "cluster0_server1", 'terminated', 'esmet'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      expect(Cluster.clusters(test_config).keys).to eql ['cluster0']
    end

    it "returns nothing if no servers are in the running state" do
      sample_servers = [
        AwsServerMock.new('cluster0', "cluster0_server0", 'terminated', 'esmet'),
        AwsServerMock.new('cluster1', "cluster1_server0", 'terminated', 'esmet'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      expect(Cluster.clusters(test_config).keys).to eql []
    end
  end

  describe "#servers" do
    it "returns a hash of string names => server" do
      sample_servers = [
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server0", 'running', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server1", 'running', 'esmet'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      cluster = Cluster.new test_options, test_config
      cluster.servers.should eql({
        "#{test_cluster_name}_server0" => sample_servers[0],
        "#{test_cluster_name}_server1" => sample_servers[1],
      })
    end

    it "only returns servers whose name tag is prefixed by the cluster name" do
      sample_servers = [
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server0", 'running', 'esmet'),
        AwsServerMock.new("innocent", "innocent_cluster_server0", 'running', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server1", 'running', 'esmet'),
        AwsServerMock.new("innocent", "innocent_cluster_server1", 'running', 'esmet'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      cluster = Cluster.new test_options, test_config
      cluster.servers.should eql({
        "#{test_cluster_name}_server0" => sample_servers[0],
        "#{test_cluster_name}_server1" => sample_servers[2],
      })
    end

    it "only returns servers that were created by the api key 'esmet'" do
      sample_servers = [
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server0", 'running', 'rfp'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server1", 'running', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server2", 'running', 'leifwalsh'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      cluster = Cluster.new test_options, test_config
      cluster.servers.should eql({
        "#{test_cluster_name}_server1" => sample_servers[1],
      })
    end

    it "only returns servers in the running or pending state" do
      sample_servers = [
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server0", 'terminated', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server1", 'annihilated', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server2", 'running', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server3", 'pending', 'esmet'),
      ]
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      cluster = Cluster.new test_options, test_config
      cluster.servers.should eql({
        "#{test_cluster_name}_server2" => sample_servers[2],
        "#{test_cluster_name}_server3" => sample_servers[3],
      })
    end
  end

  describe "server management" do
    let :sample_servers do
      [ AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server0", 'running', 'esmet'),
        AwsServerMock.new(test_cluster_name, "#{test_cluster_name}_server1", 'running', 'esmet') ]
    end

    before :each do
      allow_any_instance_of(Cluster).to receive(:knife_ec2_server_create).and_return(true)
      allow_any_instance_of(Cluster).to receive(:knife_ec2_server_delete).and_return(true)
      Fog::Compute.stub(:new) { FogComputeMock.new sample_servers }
      @cluster = Cluster.new test_options, test_config
    end

    describe "#spinup" do
      it "should create servers that do not exist" do
        ok = @cluster.spinup test_cluster_name, "#{test_cluster_name}_server100", "recipes", { attr: 1 }
        expect(ok).to be_true

        ok = @cluster.spinup test_cluster_name, "another_cluster_name_server0", "recipes", { attr: 1 }
        expect(ok).to be_true
      end

      it "should raise an error when trying to spin up a server that already exist" do
        lambda { @cluster.spinup test_cluster_name, "#{test_cluster_name}_server0", "recipes", { attr: 1 } }.should raise_error
        lambda { @cluster.spinup test_cluster_name, "#{test_cluster_name}_server1", "recipes", { attr: 1 } }.should raise_error
      end
    end

    describe "#teardown" do
      it "returns N when tearing down an N-node cluster" do
        expect(@cluster.teardown).to eq(sample_servers.size)
      end

      it "returns 0 when tearing down an empty cluster" do
        Fog::Compute.stub(:new) { FogComputeMock.new }
        cluster = Cluster.new test_options, test_config
        expect(cluster.teardown).to eq(0)
      end
    end
  end
end
