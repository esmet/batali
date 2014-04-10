require 'ostruct'

require_relative '../lib/batali/chef.rb'

include Batali

describe Chef do
  describe "#new" do
    it "requires an options struct with the knife_config_file field" do
      lambda { Chef.new }.should raise_exception
      lambda { Chef.new OpenStruct.new }.should raise_exception
    end
  end
end
