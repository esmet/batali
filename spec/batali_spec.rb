require_relative '../lib/batali.rb'

class ChefMock
  attr_reader :config

  def initialize cookbooks, config = {}
    @cookbooks = cookbooks
    @config = config
  end

  def cookbooks
    Hash[@cookbooks.collect { |cookbook| [ cookbook, Object.new ] }]
  end
end

include Batali

describe Batali do
  describe "#new" do
    batali_required_cookbooks = [ 'apt', 'mongodb', 'tokumx' ]

    context "all cookbooks are available through Chef" do
      before do
        Chef.stub(:new) { ChefMock.new batali_required_cookbooks }
      end

      it "succeeds" do
        Batali.new OpenStruct.new
      end
    end

    context "at least one cookbook is missing" do
      batali_required_cookbooks.each do |cookbook|
        it "fails when cookbook '#{cookbook}' is missing" do
          Chef.stub(:new) { ChefMock.new(batali_required_cookbooks - [ cookbook ]) }
          lambda { Batali.new OpenStruct.new }.should raise_error(/cookbook not found/)
        end
      end
    end

    it "sets the config field to Chef's config" do
      config = { mocked: true }
      Chef.stub(:new) { ChefMock.new batali_required_cookbooks, config }
      batali = Batali.new OpenStruct.new
      batali.instance_variable_get(:@config).should eql config
    end
  end
end
