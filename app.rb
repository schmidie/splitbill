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
require 'joint'

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
  key :deleted, Boolean
  key :name,        String
  key :location,      String
  key :open, Boolean
  key :creator_pays, Boolean
  key :add_bill, Boolean
  key :date, Date
  many :items
  many :payments
  many :logs
  many :comments
  key :members, Array
  many :mm_users , :in => :members
  timestamps!
  
  validates_presence_of :name
  validates_presence_of :location
  validates_presence_of :date
 
  
end

class Item
  include MongoMapper::EmbeddedDocument
  plugin Joint

  attachment :bill
  belongs_to  :mm_user
  embedded_in :event
  key :name,    String
  key :amount,   Float
  validates_presence_of :name
  validates_presence_of :amount
  validates_numericality_of :amount

end

class Payment
  include MongoMapper::EmbeddedDocument
  embedded_in :event
  belongs_to  :mm_user
  key :amount,   Float
  key :payed, Boolean
  key :recieved, Boolean
end

class Log
  include MongoMapper::EmbeddedDocument
  embedded_in :event
  belongs_to  :mm_user
  key :message, String
  key :object, String
  timestamps!
end

class Comment
  include MongoMapper::EmbeddedDocument
  embedded_in :event
  belongs_to  :mm_user
  key :message, String
  timestamps!
end

# Before Filter
before do
  session[:locale] = params[:locale] if params[:locale]
end


# Helper
helpers do
  def statistics
     sum=0;
     count_e=0;
     count_p=0;
     @events = Event.all
     @events.each do |event|
       event.items.each do |item|
         sum += item.amount
         count_p+=1
       end
       count_e+=1
     end
     @stats = { :events => count_e, :items => count_p , :sum => sum }
     haml :stats
  end
  def error? var,key
    var.respond_to?(:errors) && (var.errors.has_key? key)
  end
end


get '/' do
  login_required
	show_events
end

def show_events
  @events = Event.all(:deleted => false , :order => :created_at.desc)
  @trash = Event.all(:deleted => true, :mm_user_id => current_user._id , :order => :created_at.desc)
  haml :index
end

post '/create' do
  login_required
  if params[:event][:add_bill]== "true"
    params[:event][:add_bill] = true
  else
    params[:event][:add_bill] = false
  end
  if params[:event][:creator_pays]== "true"
    params[:event][:creator_pays] = true
  else
    params[:event][:creator_pays] = false
  end
  @event = Event.new(params[:event])
  @event.mm_user = current_user
  @event.open = true
  @event.deleted = false
  if @event.valid?
    @event.save
    redirect "/events/#{@event._id}"
  else
    show_events
  end
end

get '/events/:id' do |id|
   login_required
   @event = Event.find(id)
   show_event 
end

def show_event 
   calculate_sum_and_part
   @creator = @event.mm_user_id == current_user.id  
   haml :show
end

post '/events/:id/edit'do |id|
   login_required
   if params[:event][:add_bill]== "true"
    params[:event][:add_bill] = true
  else
    params[:event][:add_bill] = false
  end
  if params[:event][:creator_pays]== "true"
    params[:event][:creator_pays] = true
  else
    params[:event][:creator_pays] = false
  end
   @event = Event.find(id)
   if @event.open && @event.mm_user._id == current_user._id
    @event.update_attributes(params[:event])
    if @event.valid?
      @event.save
      redirect "/events/#{@event._id}"
    else
      haml :form
    end
   end
  
end

get '/events/:id/edit'do |id|
   login_required
   @event = Event.find(id)
   haml :form
end

get '/events/:id/delete'do |id|
   login_required
   @event = Event.find(id)
   if @event.open && @event.mm_user._id == current_user._id
    @event.deleted = true
    @event.save
   end
  redirect "/"
end

get '/events/:id/undelete'do |id|
   login_required
   @event = Event.find(id)
   if @event.open && @event.mm_user._id == current_user._id
    @event.deleted = false
    @event.save
   end
  redirect "/"
end

get '/events/:id/join' do |id|
  login_required
  @event = Event.find(id)
  if @event.open
    log = Log.new(:mm_user => current_user, :message => "participate" , :object => current_user.email)
    @event.logs << log
    @event.save
    @event.push({:members => current_user._id})
  end
  redirect "/events/#{@event._id}"
end

post '/events/:id/add' do |id|
   login_required
  
   @event = Event.find(id)
   if @event.members.include? current_user.id 
     if @event.open
       @item = Item.new(:name => params[:item][:name], :amount => params[:item][:amount] )
       if params[:item][:bill]
         @item.bill = params[:item][:bill][:tempfile]
       else
         if @event.add_bill
           flash[:error] = t.event.please_add_bill
           redirect "/events/#{@event._id}"
           return
         end
       end
       
       if @item.valid?
         
           @item.mm_user = current_user
           @event.items << @item
           log = Log.new(:mm_user => current_user, :message => "item_added" , :object => @item.name)
           @event.logs << log
        
           @event.save
           redirect "/events/#{@event._id}"
        
       else
         show_event
       end
     else
       flash[:error] = t.errors.closed
       redirect "/events/#{@event._id}"
     end
   else
     flash[:error] = t.errors.participate
     redirect "/events/#{@event._id}"
   end
   
end

get '/events/:id/:item_id/delete' do |id,item_id|
   login_required
   @event = Event.find(id)
   if @event.open
     @event.items.each do |item|
       if item.id.to_s == item_id && (item.mm_user_id == current_user.id || event.mm_user_id == current_user.id) 
          @item = item
          log = Log.new(:mm_user => current_user, :message => "item_deleted" , :object => item.name)
          @event.logs << log
          @event.save
          @event.pull( :items => {:_id => item.id})
         
       end
     end
   else
       flash[:error] = t.errors.closed
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
   if @event.open
       @event.items.each do |item|
         if(item.id.to_s == item_id && item.mm_user_id == current_user.id) 
          item.name = params[:item][:name]
          item.amount = params[:item][:amount]
          @item = item
          log = Log.new(:mm_user => current_user, :message => "item_edited" , :object => item.name)
          @event.logs << log
          if @item.valid?
            @event.save
            redirect "/events/#{@event._id}"
          else
            return haml :edit
          end
         end
       end
   else
       flash[:error] = t.errors.closed
       redirect "/events/#{@event._id}"
   end

   
end

get '/events/:id/close' do |id|
   login_required
   @event = Event.find(id)
   if @event.mm_user_id == current_user.id
      @event.open = false
      @event.save
      # Event Closed !
      calculate_sum_and_part
      @members.each do |member| 
        itemamount = calculate_member_amount member
        payment = Payment.new( {:mm_user => member, :amount => (@part-itemamount),:payed => false, :recieved => false} )
        @event.payments << payment
      end
      log = Log.new(:mm_user => current_user, :message => "closed" , :object => @event.name)
      @event.logs << log
      @event.save
   end
   redirect "/events/#{@event._id}"
end

get '/bills/:id/:item_id' do |id,item_id|
  login_required
  @event = Event.find(id)
   
   @event.items.each do |item|
     if item.id.to_s == item_id
        @item = item
     end
   end
   file = @item.bill
  [200, {'Content-Type' => file.content_type}, [file.read]]

end


get '/events/:id/pay/:payment_id' do |id,payment_id|
   login_required
   @event = Event.find(id)
   @event.payments.each do |payment|
       if payment.id.to_s == payment_id 
         if (payment.mm_user_id == current_user.id && payment.amount > 0) || (@event.mm_user_id == current_user.id   && payment.amount <= 0)
            payment.payed = true
            @event.save
         end
       end
   end
  
   redirect "/events/#{@event._id}"
end

get '/events/:id/recieve/:payment_id' do |id,payment_id|
   login_required
   @event = Event.find(id)
   @event.payments.each do |payment|
       if payment.id.to_s == payment_id 
         if (@event.mm_user_id == current_user.id   && payment.amount > 0) || (payment.amount <= 0 && payment.mm_user_id == current_user.id)
            payment.recieved = true
            @event.save
         end
       end
   end
  
   redirect "/events/#{@event._id}"
end

post '/events/:id/comment' do |id| 
  login_required
   @event = Event.find(id)
   comment = Comment.new(params[:comment] )
   comment.mm_user = current_user
   @event.comments << comment
   
   @event.save
  
   redirect "/events/#{@event._id}"
end


def calculate_member_amount member
  sum = 0
  @event.items.each do |item|
    if item.mm_user == member
      sum += item.amount
    end
  end
  sum
end

def calculate_sum_and_part
      @sum = 0
      @members = MmUser.find @event.members
      @event.items.each do |item|
        @sum += item.amount
      end
      if @event.members.count != 0 && !@event.creator_pays
        @part = @sum/@event.members.count
      else
        @part = 0
      end
end
