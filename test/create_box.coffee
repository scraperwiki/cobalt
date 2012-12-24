# create_box.coffee

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

nocks = require '../test/nocks'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000'

describe 'Creating a box:', ->
  apikey = String(Math.random()).replace('0.', '')

  after ->
    nock.cleanAll()

  describe '( POST /<boxname> )', ->
    server = null
    exec_stub = null
    newboxname = String(Math.random()).replace('0.','')

    before (done) ->
      server = require 'serv'
      sinon.stub console, 'tick'
      exec_stub = sinon.stub server, 'unix_user_add', (_a, callback) ->
        callback null, null, null

      User.collection.drop ->
        Box.collection.drop ->
          new User({apikey: apikey, shortname: 'kiteorg'}).save done

    it 'gives an error when creating a databox without a key', (done) ->
      u = "#{baseurl}/box/#{newboxname}"
      request.post {url:u}, (err, resp, body) ->
        resp.statusCode.should.equal 403
        (_.isEqual (JSON.parse resp.body), {'error':'No API key supplied'}).should.be.true
        done()

    describe 'when the apikey is valid', ->
      response = null

      before (done) ->
        options =
          uri: "#{baseurl}/box/#{newboxname}"
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it "doesn't return an error", ->
        (_.isEqual (JSON.parse response.body), {status:"ok"}).should.be.true
        response.statusCode.should.equal 200

      it 'calls the useradd command with appropriate args', ->
        exec_stub.called.should.be.true
        exec_stub.calledWith newboxname

      it 'adds the box to the database', (done) ->
        Box.findOne {name: newboxname}, (err, box) ->
          should.exist box
          done()

      it 'errors when the box already exists', (done) ->
        options =
          uri: "#{baseurl}/box/#{newboxname}"
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
          (_.isEqual (JSON.parse resp.body), {error:"Box already exists"}).should.be.true
          done()


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

