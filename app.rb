require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'sinatra/url_for'

require 'ostruct'
require 'time_diff'
require 'active_support/all'

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

  if clusters.size == 0
    sub_header = "No clusters online"
  else
    sub_header = "#{clusters.size} cluster#{clusters.size == 1 ? '' : 's'} online"
  end

  erb :dashboard, :locals => {
    header: 'Dashboard',
    sub_header: sub_header,
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
    column_names: [ 'Name', 'Flavor', 'URL' ],
    table_rows: servers.collect { |name, server_info| [ name, server_info[:flavor], server_info[:url] ] },
  }
end

def get_modify_page_for_create(locals = {})
  locals = {
    header: 'Create a cluster',
    sub_header: "Choose a quantity for each server. Flavor applies to all.",
    create: true,
    error_message: '',
  }.merge(locals)
  erb :modify_cluster, locals: locals
end

def get_modify_page_for_modify(locals = {})
  locals = {
    header: 'Modify a cluster',
    sub_header: "Choose a new quantity for each server (will only expand the cluster).",
    create: false,
    error_message: '',
  }.merge(locals)
  erb :modify_cluster, locals: locals
end

def default_one(field)
  x = field.to_i
  x <= 0 ? 1 : x
end

# by some absolute ridiculous black magic, the 'batali'
# parameter here is necessary, otherwise sinatra just
# fails silently (SILENTLY) the first time you reference it.
def do_modify_and_get_request_sent_page(batali, params)
  # create the cluster..
  name = params[:name]
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
end

# modify cluster

get '/modify_cluster' do
  name = (params[:name] || '')
  if name != ''
    get_modify_page_for_modify params
  end
end

post '/modify_cluster' do
  name = (params[:name] || '')
  if name != ''
    do_modify_and_get_request_sent_page batali, params
  end
end

# create cluster

get '/create_cluster/?' do
  get_modify_page_for_create
end

post '/create_cluster' do
  name = (params[:name] || '')
  if name == ''
    get_modify_page_for_create({
      error_message: "Need to provide a cluster name"
    })
  elsif batali.clusters.include?(name)
    get_modify_page_for_create({
      error_message: "A cluster named '#{name}' already exists"
    })
  else
    do_modify_and_get_request_sent_page batali, params
  end
end

# teardown cluster

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
  end
end
