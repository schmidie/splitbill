require 'sinatra'
require 'haml'
require "digest/sha1"
require 'mongo_mapper'
require 'sinatra-authentication'
require 'sinatra/flash'
require 'sinatra/form_helpers'

#Sinatra-Flash Hack
module Rack
  class Flash
	end
end

#Auth
use Rack::Session::Cookie, :secret => 'mongoid and sinatra does the body good'
set :sinatra_authentication_view_path, Pathname(__FILE__).dirname.expand_path + "views/auth/"

#MongoMapper Config

configure do
	MongoMapper.database = 'splitbill'
end

# Mongo Documents

class Event
  include MongoMapper::Document
  belongs_to  :mm_user
  key :name,        String
  key :location,      String
  key :date, Date
  many :items
  timestamps!
end

class Item
  include MongoMapper::EmbeddedDocument
  key :name,    String
  key :amount,   Float
end

get '/' do
	login_required
	@events = Event.sort(:created_at.desc)
	haml :index
end

post '/create' do
  
  eventparam = 
  @event = Event.new(params[:event])
  @event.mm_user = current_user
  @event.save
  redirect "/events/#{@event._id}"
end

get '/events/:id' do |id|
   @event = Event.find(id)
   haml :show
end

