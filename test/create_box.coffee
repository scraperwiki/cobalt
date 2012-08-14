# basic.coffee

http = require 'http'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
nock   = require 'nock'
sinon  = require 'sinon'
_ = require 'underscore'

mongoose = require 'mongoose'
User = require 'models/user'
Box = require 'models/box'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000/'

describe 'Creating a box:', ->
  describe '( POST /<box_name> )', ->
    server = null
    exec_stub = null

    before (done) ->
      server = require 'serv'
      User.collection.drop()
      Box.collection.drop()
      exec_stub = sinon.stub server, 'unix_user_add', (_a, cb) ->
        cb null, null, null
      done()

    after (done) ->
      mongoose.disconnect ->
        done()

    it 'gives an error when creating a databox without a key', (done) ->
      u = baseurl + 'newdatabox'
      request.post {url:u}, (err, resp, body) ->
        resp.statusCode.should.equal 403
        (_.isEqual (JSON.parse resp.body), {'error':'No API key supplied'}).should.be.true
        done()

    describe 'when the apikey is valid', ->
      froth = null
      response = null
      apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

      before (done) ->

        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options =
          uri: baseurl + 'newdatabox'
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it 'requests validation from froth', ->
        froth.isDone().should.be.true

      it "doesn't return an error", ->
        (_.isEqual (JSON.parse response.body), {status:"ok"}).should.be.true
        response.statusCode.should.equal 200

      it 'calls the useradd command with appropriate args', ->
        exec_stub.called.should.be.true
        exec_stub.calledWith 'newdatabox'

      it 'adds the user to the database', (done) ->
        User.findOne {apikey: apikey}, (err, user) ->
          should.exist user
          done()

      it 'adds the box to the database', (done) ->
        Box.findOne {name: 'newdatabox'}, (err, box) ->
          should.exist box
          done()

      it 'errors when the box already exists', (done) ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options =
          uri: baseurl + 'newdatabox'
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
          (_.isEqual (JSON.parse resp.body), {error:"Box already exists"}).should.be.true
          done()


    describe 'when we use a naughty box name', ->
      froth = null
      response = null
      exec_stub = null
      apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

      before (done) ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options =
          uri: baseurl + 'box;with silly characters!'
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it "returns an error", ->
        response.statusCode.should.equal 404


    describe 'when the apikey is invalid', ->
      before ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/junk")
        .reply 403, "403", { 'content-type': 'text/plain' }

      it 'returns an error', (done) ->
        options =
          uri: baseurl + 'newdatabox'
          form:
            apikey: 'junk'

        request.post options, (err, resp, body) ->
            resp.statusCode.should.equal 403
            (_.isEqual (JSON.parse resp.body), {'error':'Unauthorised'}).should.be.true
            done()

