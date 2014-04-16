require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'sinatra/url_for'

require 'ostruct'
require 'time_diff'

set :bind, '0.0.0.0'
set :port, '5757'
set :public_folder, 'public'

require_relative 'lib/batali'
options = OpenStruct.new(knife_config_file: '.batali/knife.rb', verbose: true)
batali = Batali.new options

get '/?' do
  redirect url_for('/dashboard')
end

get '/dashboard' do
  filter = params[:filter] || ''
  clusters = batali.clusters.collect do |cluster, servers|
    if filter == '' ||
       cluster.match(filter) ||
       cluster.include?(filter)
      [ cluster, servers ]
    end
  end.compact
  clusters = Hash[clusters]

  erb :dashboard, :locals => {
    header: 'Dashboard',
    sub_header: "#{clusters.size} cluster#{clusters.size == 1 ? '' : 's'} online",
    clusters: clusters,
  }
end

get '/manage_cluster' do
  name = params[:name] || ''
  servers = {}
  if name != ''
    servers = batali.show(OpenStruct.new(cluster: params[:name])).sort
  end

  erb :manage_cluster, :locals => {
    header: name == '' ?  "Search clusters" : "Showing cluster '#{name}'",
    sub_header: servers.size > 0 ? "#{servers.size} server#{servers.size == 1 ? '' : 's'} found" : "No servers found",
    cluster_name: name,
    column_names: [ 'Name', 'URL' ],
    table_rows: servers.collect { |name, dns_name| [ name, dns_name ] },
  }
end

get '/create_cluster/?' do
  erb :create_cluster
end

def default_one(field)
  x = field.to_i
  x <= 0 ? 1 : x
end

post '/create_cluster' do
  name = (params[:name] || '')
  if name != ''
    # create the cluster..
    options = OpenStruct.new({
      cluster:        name,
      config_servers: default_one(params[:config_servers]),
      shards:         default_one(params[:shards]),
      rs_members:     default_one(params[:rs_members]),
      mongos_routers: default_one(params[:mongos_routers]),
      flavor:         params[:flavor] || '',
    })
    # (on a background thread)
    thr = Thread.new do
      batali.cook options
    end
    # ..then show the request sent page with the given name
    erb :request_sent, :locals => {
      name: name
    }
  else
    # show the create page
    erb :create_cluster
  end
end

get '/teardown_cluster' do
  name = (params[:name] || '')
  if name != ''
    # teardown the cluster..
    options = OpenStruct.new({
      cluster:  name,
      teardown: true,
    })
    # (on a background thread)
    thr = Thread.new do
      batali.teardown options
    end
    # ..then show the request sent page with the given name
    erb :request_sent, :locals => {
      name: name
    }
  else
    # just show the manage page for empty teardown requests
    redirect url_for("/manage_cluster?name=#{name}")
  end
end
