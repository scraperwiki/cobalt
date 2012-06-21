# basic.coffee

http = require 'http'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
nock   = require 'nock'
sinon  = require 'sinon'

mongoose = require 'mongoose'
User = require 'models/user'
Box = require 'models/box'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000/'

describe 'server', ->
  server = null

  before (done) ->
    server = require 'serv'
    mongoose.connect "mongodb://mong:#{process.env['COBALT_DB_PASS']}@flame.mongohq.com:27055/cobalt-test"
    User.collection.drop()
    Box.collection.drop()
    done()

  it 'can be started', (done) ->
    http.get httpopts, (err, res) ->
      done()

  it 'gives an error when creating a databox without a key', (done) ->
    u = baseurl + 'newdatabox'
    request.post {url:u}, (err, resp, body) ->
      resp.statusCode.should.equal 403
      resp.body.should.equal '{ "error": "No API key supplied" }'
      done()

  describe 'when the apikey is valid', ->
    froth = null
    response = null
    exec_stub = null
    apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

    before (done) ->
      exec_stub = sinon.stub server, 'unix_user_add', (_a, cb) ->
        cb null, null, null

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
          resp.body.should.equal '{ "error": "Unauthorised" }'
          done()
