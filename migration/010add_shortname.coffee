#!/usr/bin/env coffee
# Created 2012-11-20

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


# These are user to whom we granted premium accounts so they could trial
# boxes, then withdrew the account, so they don't appear in froth.
# Zarino collected them "by hand" using mysql on rush.
special = 
  "48fae8db-00b3-4425-993e-b255ed17b602": "henare"
  "1b771dcb-5a32-4e89-8980-0c5f509ae259": "jystewart"
  "5149dc85-15fa-4729-8327-dddd9d1688b7": "lizconlan"
  "903f2f9f-d8e6-4f23-8668-c7c64e801591": "pezholio"
  "85c48864-1d44-4db5-96a3-4942fb5a806e": "psychemedia"
  "0a29de74-5426-40e0-ac53-f63afad02108": "sunlightfoundation"
  "c755d45e-a392-4d31-8ed4-1a4e28025cd6": "swk"
  "106a95fc-78db-43fe-a818-db708bdba5f9": "tspencer"

User = mongoose.model 'User', userSchema

getShortname = (apikey, callback) ->
  url = "https://scraperwiki.com/froth/check_key/#{apikey}"
  request.get url, (err, resp, body) ->
    body = JSON.parse body
    callback body.org

main = ->
  if not process.argv[2]?
    console.log "Please specify a Mongo DB connection thingy"
    process.exit 4
  mongo = process.argv[2]
  process.stdout.write "Connecting to #{mongo}..."
  mongoose.connect mongo
  process.stdout.write "\rConnected    \n"
  each = (user, cb) ->
    getShortname user.apikey, (shortname) ->
      if user.apikey.match /\s$/
        # delete this extra special user (apikey ends with a newline)
        user.remove ->
          cb null, user
      if not shortname?
        shortname = special[user.apikey]
      console.log user.apikey, "xx #{shortname} yy"
      user.shortname = shortname
      user.save ->
        cb null, user
  User.find {}, null, {}, (err, users) ->
    async.map users, each, process.exit

main()
