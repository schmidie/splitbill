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
  key :members, Array
  many :mm_users , :in => :members
  timestamps!
end

class Item
  include MongoMapper::EmbeddedDocument
  belongs_to  :mm_user
  embedded_in :event
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
   @members = MmUser.find @event.members
   @event.items.each do |item|
     @sum += item.amount
   end
   haml :show
end

get '/events/:id/join' do |id|
  login_required
  @event = Event.find(id)
  @event.push({:members => current_user._id})
  redirect "/events/#{@event._id}"
end

post '/events/:id/add' do |id|
   login_required
  
   @event = Event.find(id)
   if event.members.include? current_user.id
     item = Item.new(params[:item])
     item.mm_user = current_user
     @event.items << item
     @event.save
   end
   redirect "/events/#{@event._id}"
end

get '/events/:id/:item_id/delete' do |id,item_id|
   login_required
   @event = Event.find(id)
   
   @event.items.each do |item|
     if item.id.to_s == item_id && item.mm_user_id == current_user.id
        @item = item
        @event.pull( :items => {:_id => item.id})
     end
   end

   redirect "/events/#{@event._id}"
end

get '/events/:id/:item_id/edit' do |id,item_id|
   login_required
   @event = Event.find(id)
   
   @event.items.each do |item|
     if item.id.to_s == item_id && item.mm_user_id == current_user.id
        @item = item
     end
   end

   haml :edit
end

post '/events/:id/:item_id/edit' do |id,item_id|
   login_required
   @event = Event.find(id)
   
   @event.items.select{|item| item.id.to_s == item_id}.each{}

   haml :edit
end
