# basic.coffee

fs = require 'fs'

request = require 'request'
should = require 'should'
nock   = require 'nock'
sinon  = require 'sinon'

mongoose = require 'mongoose'
server = require 'serv'
User = require 'models/user'
Box = require 'models/box'

nocks = require '../test/nocks'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000/'

APIKEY = '342709d1-45b0-2d2e-sd66-6fb81d10e34e'
BOX = 'kiteorg/oldproject'
box_url = baseurl + BOX

describe 'Box documentation', ->
  read_stub = null

  beforeEach ->
    read_stub = sinon.stub(fs, 'readFile')
      .withArgs("/home/#{BOX}/scraperwiki.json")
      .callsArgWith(2, {code: 'ENOENT'}, null)

  afterEach ->
    fs.readFile.restore()

  describe '( GET / )', ->

    it 'documents how to create a box', (done) ->
      request.get {url:baseurl}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'reate'
        resp.body.should.include 'API'
        resp.body.should.include 'curl'
        JSON.parse resp.body
        done()

  describe '( GET /<org>/<project> )', ->

    before (done) ->
      User.collection.drop()
      Box.collection.drop()

      new User({apikey: APIKEY}).save()
      User.findOne {apikey: APIKEY}, (err, user) ->
        console.log err if err
        new Box({user: user._id, name: BOX}).save()
        done()

    it 'documents how to SSH into a box', (done) ->
      request.get {url:box_url}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'ssh'
        resp.body.should.include 'curl'
        resp.body.should.include '@'
        JSON.parse resp.body
        done()
        
    it 'documents how to access web endpoint of box', (done) ->
      request.get {url:box_url}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'https://127.0.0.1:3000/' + BOX + '/http'
        JSON.parse resp.body
        done()

    it 'documents how to access SQLite endpoint of box', (done) ->
      request.get {url:box_url}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'https://127.0.0.1:3000/' + BOX + '/sqlite'
        JSON.parse resp.body
        done()

    it 'documents how to supply a callback parameter to the HTTP & SQLite endpoints', (done) ->
      request.get {url:box_url}, (err, resp, body) ->
        resp.statusCode.should.equal 200
        resp.body.should.include 'JSONP'
        resp.body.should.include 'callback'
        JSON.parse resp.body
        done()

    describe 'when the box has a publishing token set', ->
      beforeEach ->
        obj =
          database: 'scraperwiki.sqlite'
          publish_token: '1234567890qwerty'

        fs.readFile.restore()
        read_stub = sinon.stub(fs, 'readFile')
          .withArgs("/home/#{BOX}/scraperwiki.json")
          .callsArgWith(2, null, JSON.stringify obj)

      describe 'when the user has access to the box', ->
        it 'documents how to use the publish token (showing it)', (done) ->
          params =
            url: box_url
            qs:
              apikey: APIKEY

          nocks.success APIKEY
          request.get params, (err, resp, body) ->
            resp.statusCode.should.equal 200
            resp.body.should.include "/1234567890qwerty/http"
            JSON.parse resp.body
            read_stub.calledOnce.should.be.true
            done()

      describe 'when the user does NOT have access to the box', ->
        it 'does not show the publish token', (done) ->
          request.get {url:box_url}, (err, resp, body) ->
            resp.statusCode.should.equal 200
            resp.body.should.not.include '1234567890qwerty'
            read_stub.calledOnce.should.be.true
            JSON.parse resp.body
            done()
