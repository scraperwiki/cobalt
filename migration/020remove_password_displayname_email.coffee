#!/usr/bin/env coffee
# Created 2012-12-20
# Removes various fields from User documents in a mongo database.
# The database is specified on the command line.

async = require 'async'
mongoose = require 'mongoose'
request = require 'request'

# This is the old User schema, copied into here.
Schema = mongoose.Schema
userSchema = new Schema
  apikey: {type: String, unique: true}
  email: [String]
  displayname: String
  password: String
  isstaff: Boolean
  shortname: String

User = mongoose.model 'User', userSchema

main = ->
  if not process.argv[2]?
    console.log "Please specify a Mongo DB connection thingy"
    process.exit 4
  mongo = process.argv[2]
  process.stdout.write "Connecting to #{mongo}..."
  mongoose.connect mongo
  process.stdout.write "\rConnected    \n"
  each = (user, cb) ->
    User.update({_id: user._id}, {$unset: {password: 1}}).exec()
    User.update({_id: user._id}, {$unset: {email: 1}}).exec()
    User.update({_id: user._id}, {$unset: {displayname: 1}}).exec()
    cb null, user
  User.find {}, null, {}, (err, users) ->
    async.map users, each, process.exit

main()
