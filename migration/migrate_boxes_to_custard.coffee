#!/usr/bin/env coffee
fs = require 'fs'

request = require 'request'
mongoose = require 'mongoose'
async = require 'async'

cobalt = mongoose.createConnection process.env['COBALT_DB']
custard = mongoose.createConnection process.env['CU_DB']

User = require 'models/user'
Box = require 'models/box'

CobaltUser = cobalt.model 'User', User
CobaltBox = cobalt.model 'Box', Box

CustardUser = custard.model 'User', User
CustardBox = custard.model 'Box', Box

custard.on 'error', (err, b ) ->
  console.log err, b

cobalt.on 'error', (err, b ) ->
  console.log err, b

getUserFromBox = (box, cb) ->
  cb() unless box?
  CobaltUser.findOne {_id: box.user}, (err, user) ->
    console.log err if err?
    #console.log "#{box?.name} #{user?.shortname}"
    if box?.name? and user?.shortname
      CustardUser.findOne {shortName: user.shortname}, (err, cusUser) ->
        if cusUser?
          custardBox = new CustardBox
            name: box.name
            users: [cusUser.shortName]
          console.log custardBox
          return custardBox.save (err) ->
            console.log "ERROR: #{err}" if err?
            return cb()
        else
          console.log "ERROR: #{user.shortname} not found in custard"
    return cb()

CobaltBox.find {}, (err, boxes) ->
  async.forEach boxes, getUserFromBox, (err, res) ->
    console.log err, res
    #process.exit 0
