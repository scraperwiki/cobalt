#!/usr/bin/env coffee
# Created 2012-12-28
# Replaces slashes in box names with dots
# The database is specified on the command line.

async = require 'async'
mongoose = require 'mongoose'
request = require 'request'

# This is the Box schema, copied into here.
boxSchema = new mongoose.Schema
  user: mongoose.Schema.ObjectId
  name: {type: String, unique: true}

Box = mongoose.model 'Box', boxSchema

main = ->
  if not process.argv[2]?
    console.log "Please specify a Mongo DB connection thingy"
    process.exit 4
  mongo = process.argv[2]
  process.stdout.write "Connecting to #{mongo}..."
  mongoose.connect mongo
  process.stdout.write "\rConnected    \n"
  each = (box, cb) ->
    box.name = box.name.replace('/', '.')
    box.save (err) ->
      cb err, box
  Box.find {}, null, {}, (err, boxes) ->
    async.map boxes, each, process.exit

main()
