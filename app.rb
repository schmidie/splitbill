require "rubygems"
require "bundler/setup"
require 'sinatra'
require 'haml'
require "digest/sha1"
require 'mongo_mapper'
require 'sinatra-authentication'
require 'sinatra/flash'
require 'sinatra/form_helpers'
require 'sinatra/r18n'
require 'money'

#Sinatra-Flash Hack
module Rack
  class Flash
	end
end

#Auth
use Rack::Session::Cookie, :secret => 'mongoid and sinatra does the body good'
set :sinatra_authentication_view_path, Pathname(__FILE__).dirname.expand_path + "views/auth/"


#I18n


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
  belongs_to  :mm_user
  key :name,    String
  key :amount,   Float
end

before do
  session[:locale] = params[:locale] if params[:locale]
end

get '/' do
	login_required
	@events = Event.sort(:created_at.desc)
	haml :index
end

post '/create' do
  login_required
  @event = Event.new(params[:event])
  @event.mm_user = current_user
  @event.save
  redirect "/events/#{@event._id}"
end

get '/events/:id' do |id|
   login_required
   @event = Event.find(id)
   @sum = 0
   @event.items.each do |item|
     @sum += item.amount
   end
   haml :show
end

post '/events/:id/add' do |id|
   login_required
   @event = Event.find(id)
   item = Item.new(params[:item])
   item.mm_user = current_user
   @event.items << item
   @event.save
   redirect "/events/#{@event._id}"
end

get '/events/:id/:item/delete' do |id,item|
   login_required
   @event = Event.find(id)
   @event.pull( :items => {:_id => BSON::ObjectId(item)})
   redirect "/events/#{@event._id}"
  
end
