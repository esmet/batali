require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'sinatra/url_for'

require 'ostruct'
require_relative 'lib/batali'

set :bind, '0.0.0.0'
set :port, '5757'
set :public_folder, 'public'

options = OpenStruct.new knife_config_file: '.batali/knife.rb', dry: true
batali = Batali.new options

get '/?' do
  redirect url_for('/dashboard')
end

get '/dashboard' do
  @servers = {}
  if params[:search]
    @servers = batali.show OpenStruct.new(cluster: params[:search])
  end
  erb :dashboard
end
