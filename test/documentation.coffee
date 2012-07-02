# basic.coffee

http = require 'http'
request = require 'request'
should = require 'should'
nock   = require 'nock'
sinon  = require 'sinon'

mongoose = require 'mongoose'
User = require 'models/user'
Box = require 'models/box'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000/'

APIKEY = '342709d1-45b0-2d2e-sd66-6fb81d10e34e'
BOX = 'olddatabox'

describe 'Box documentation', ->
  describe '( GET / )', ->
    server = null

    before (done) ->
      server = require 'serv'
      done()

    it 'documents how to create a box', (done) ->
      u = baseurl
      request.get {url:u}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'reate'
        resp.body.should.include 'API'
        resp.body.should.include 'curl'
        done()

  describe '( GET /<box_name> )', ->
    server = null

    before (done) ->
      server = require 'serv'
      mongoose.connect process.env['COBALT_DB']
      User.collection.drop()
      Box.collection.drop()

      new User({apikey: APIKEY}).save()
      User.findOne {apikey: APIKEY}, (err, user) ->
        new Box({user: user._id, name: BOX}).save()

      done()

    it 'documents how to SSH into a box', (done) ->
      u = baseurl + BOX
      request.get {url:u}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'ssh'
        resp.body.should.include 'curl'
        resp.body.should.include '@'
        done()

