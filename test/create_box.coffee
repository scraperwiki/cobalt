# create_box.coffee

http = require 'http'

# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
sinon  = require 'sinon'
_ = require 'underscore'
mongoose = require 'mongoose'

User = require 'models/user'
Box = require 'models/box'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000'

describe 'Creating a box:', ->
  apikey = String(Math.random()).replace('0.', '')

  describe '( POST /<boxname> )', ->
    exec_stub = null
    newboxname = String(Math.random()).replace('0.','')

    before (done) ->
      @server = require 'server'
      sinon.stub console, 'tick'
      exec_stub = sinon.stub @server, 'unix_user_add', (_a, _b, callback) ->
        obj =
          publish_token: '32424dfsdr3'
          database: 'scraperwiki.sqlite'
        callback null, JSON.stringify(obj), null

      @server.start (err) ->
        User.collection.drop ->
          Box.collection.drop ->
            new User({apikey: apikey, shortName: 'kiteorg'}).save done

    after (done) ->
      console.tick.restore()
      @server.unix_user_add.restore()
      @server.stop (err) ->
        done(err)

    it "gives an error when creating a databox without a key", (done) ->
      options =
        uri: "#{baseurl}/box/#{newboxname}"
      request.post options, (err, resp, body) ->
        resp.statusCode.should.equal 403
        (_.isEqual (JSON.parse resp.body), {'error':'No API key supplied'}).should.be.true
        done()
    
    it 'gives an error when creating a databox without a uid', (done) ->
      options =
        uri: "#{baseurl}/box/#{newboxname}"
        form:
          apikey: apikey
      request.post options, (err, resp, body) ->
        resp.statusCode.should.equal 400
        (_.isEqual (JSON.parse resp.body), {'error':'Specify a UID'}).should.be.true
        done()

    describe 'when the apikey is valid', ->
      response = null

      before (done) ->
        options =
          uri: "#{baseurl}/box/#{newboxname}"
          form:
            apikey: apikey
            uid: 42

        request.post options, (err, resp, body) ->
          response = resp
          done()

      it "doesn't return an error", ->
        response.statusCode.should.equal 200

      it 'returns valid JSON', ->
        JSON.parse response.body

      it 'calls the useradd command with appropriate args', ->
        exec_stub.called.should.be.true
        exec_stub.calledWith newboxname


    describe 'when we use silly characters in a box name', ->
      response = null
      apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

      before (done) ->
        options =
          uri: "#{baseurl}/box/box;with silly characters!"
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
          response = resp
          done()

      it "returns an error", ->
        response.statusCode.should.equal 404


    describe 'when the apikey is invalid', ->
      it 'returns an error', (done) ->
        options =
          uri: "#{baseurl}/box/#{newboxname}"
          form:
            apikey: 'junk'

        request.post options, (err, resp, body) ->
          resp.statusCode.should.equal 403
          (_.isEqual (JSON.parse resp.body), {'error':'Unauthorised'}).should.be.true
          done()
