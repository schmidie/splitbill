splitbill
=========

Billing System

Depends on:
----------------
* Ruby 1.9
* MongoDB

Installation:
----------------
	bundle install

Startup:
----------------
	ruby app.rb


Known Issues:
----------------
	Command 'filemd5' failed: need an index on { files_id : 1 , n : 1 } (response: { "errmsg" : "need an index on { files_id : 1 , n : 1 }", "ok" : 0.0 })
	
Start Mongo-Shell 
	mongo
Select DB
	use splitbill
Ensure Index	
	db.fs.chunks.ensureIndex({files_id:1,n:1},{unique:true})
