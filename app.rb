require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'ostruct'
require_relative 'lib/batali'

set :bind, '0.0.0.0'
set :port, '5757'

options = OpenStruct.new knife_config_file: '.batali/knife.rb', dry: true
batali = Batali.new options
puts 'WebService: initialized Batali'

get '/' do
  erb :index
end

get '/servers/:name' do |name|
  @servers = batali.show OpenStruct.new(cluster: name)
  erb :servers
end
