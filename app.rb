require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'sinatra/url_for'

require 'ostruct'

set :bind, '0.0.0.0'
set :port, '5757'
set :public_folder, 'public'

require_relative 'lib/batali'
options = OpenStruct.new knife_config_file: '.batali/knife.rb'
batali = Batali.new options

get '/?' do
  redirect url_for('/dashboard')
end

get '/dashboard' do
  @servers = {}
  if params[:search]
    @servers = batali.show(OpenStruct.new(cluster: params[:search])).sort
  end
  erb :dashboard
end

get '/create_cluster/?' do
  erb :create_cluster
end

def default_one(field)
  x = field.to_i
  x <= 0 ? 1 : x
end

post '/create_cluster' do
  @status = ''
  @options = OpenStruct.new
  if params[:cluster] && params[:cluster] != ""
    @options = OpenStruct.new({
      cluster:        params[:cluster],
      config_servers: default_one(params[:config_servers]),
      shards:         default_one(params[:shards]),
      rs_members:     default_one(params[:rs_members]),
      mongos_routers: default_one(params[:mongos_routers]),
    })
    thr = Thread.new do
      batali.cook @options
    end
    @status = 'ok'
  end
  erb :create_cluster
end
