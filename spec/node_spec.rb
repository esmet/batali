require 'ostruct'

require_relative '../lib/batali/node.rb'

include Batali

shared_examples "a Node" do
  let :test_cluster_name do
    'test_cluster_name'
  end

  before :each  do
    @node = described_class.new OpenStruct.new({ cluster: test_cluster_name })
  end 

  describe "#new" do
    it "raises an error when the options struct has a nil or empty 'cluster' field" do
      lambda { @node.class.new OpenStruct.new }.should raise_error
      lambda { @node.class.new OpenStruct.new({ cluster: "" }) }.should raise_error
    end
  end

  describe "#name" do
    it "has a name prefixed by the cluster name" do
      @node.name.should match(/#{test_cluster_name}/)
    end
  end

  describe "#recipes" do
    it "contains the correct common recipes" do
      @node.recipes.include?('apt').should be_true
      @node.recipes.include?('tokumx::tokutek_repo').should be_true
    end
  end

  describe "#attributes" do
    it "has symbolized names" do
      @node.attributes[:mongodb].should_not be_nil
    end

    it "does not have string names" do
      @node.attributes['mongodb'].should be_nil
    end

    it "has valid values for each common attribute" do
      @node.attributes[:mongodb].should_not be_nil
      @node.attributes[:mongodb][:user].should_not be_nil
      @node.attributes[:mongodb][:group].should_not be_nil
      @node.attributes[:mongodb][:package_name].should_not be_nil
      @node.attributes[:mongodb][:config].should_not be_nil
      @node.attributes[:mongodb][:config][:logpath].should_not be_nil
      @node.attributes[:mongodb][:dbconfig_file].should_not be_nil
      @node.attributes[:mongodb][:instance_name].should_not be_nil
      @node.attributes[:mongodb][:default_init_name].should_not be_nil
    end

    it "has a cluster attribute name consistent with the provided cluster name" do
      @node.attributes[:mongodb][:cluster_name].should eql test_cluster_name
    end
  end

end

describe Node do
  it_behaves_like "a Node"
end

describe Node::ConfigServer do
  it_behaves_like "a Node"

  let :node  do
    Node::ConfigServer.new OpenStruct.new({ cluster: 'test' })
  end 

  describe "#recipes" do
    it "has the config server recipe" do
      node.recipes.include?('mongodb::configserver').should be_true
    end
  end

  describe "#attributes" do
    it "has a dbpath attribute" do
      node.attributes[:mongodb][:config][:dbpath].should_not be_nil
    end
  end
end

describe Node::Shard do
  it_behaves_like "a Node"

  let :test_cluster_name do
    'test_cluster_name'
  end

  let :test_shard_num do
    47
  end

  let :test_rs_num do
    19
  end

  before :each  do
    @node = Node::Shard.new OpenStruct.new({ cluster: test_cluster_name }), test_shard_num, test_rs_num
  end 

  describe "#name" do
    it "has a different name when shard num is different" do
      shard_num = test_shard_num + 1
      node2 = Node::Shard.new OpenStruct.new({ cluster: test_cluster_name }), shard_num, test_rs_num
      node2.name.should_not eql @node.name
    end

    it "has a different name when rs num is different" do
      rs_num = test_rs_num + 1
      node2 = Node::Shard.new OpenStruct.new({ cluster: test_cluster_name }), test_shard_num, rs_num
      node2.name.should_not eql @node.name
    end
  end

  describe "#recipes" do
    it "has the replicaset recipe" do
      @node.recipes.include?('mongodb::replicaset').should be_true
    end

    it "has the shard recipe" do
      @node.recipes.include?('mongodb::shard').should be_true
    end
  end

  describe "#attributes" do
    it "has a dbpath attribute" do
      @node.attributes[:mongodb][:config][:dbpath].should_not be_nil
    end

    it "has a shard name attribute" do
      @node.attributes[:mongodb][:shard_name].include?("shard#{test_shard_num}").should be_true
    end

    it "has a replSet attribute that contains the shard name" do
      @node.attributes[:mongodb][:config][:replSet].include?(@node.attributes[:mongodb][:shard_name]).should be_true
    end
  end
end

describe Node::Mongos do
  it_behaves_like "a Node"

  before :each  do
    @node = Node::Mongos.new OpenStruct.new({ cluster: 'test' })
  end 

  describe "#recipes" do
    it "has the mongos recipe" do
      @node.recipes.include?('mongodb::mongos').should be_true
    end
  end

  describe "#attributes" do
    # since mongos will not start with the unknown 'dbpath' parameter
    it "does not have a dbpath attribute" do
      @node.attributes[:mongodb][:config][:dbpath].should be_nil
    end
  end
end
