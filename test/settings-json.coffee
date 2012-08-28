fs     = require 'fs'

request = require 'request'
should = require 'should'
sinon  = require 'sinon'
nock   = require 'nock'
_ = require 'underscore'

User = require 'models/user'
Box = require 'models/box'
SSHKey = require 'models/ssh_key'

baseurl = 'http://127.0.0.1:3000/'

describe "scraperwiki.json settings API", ->
  server = require 'serv'
  mongoose = require 'mongoose'
  # TODO: icky, we want fixtures or mocking
  User.collection.drop()
  Box.collection.drop()

  # should we stub the readfile to return a fixture?
  describe "GET /<box_name>/settings", ->
    froth = null
    read_stub = null
    apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"
    options =
        uri: baseurl + 'newdatabox/settings/'
        form:
          apikey: apikey

    before ->
      fixture_buffer = fs.readFileSync "test/fixtures/scraperwiki.json"

      read_stub = sinon.stub(fs, 'readFileSync').withArgs("/home/newdatabox/scraperwiki.json").returns fixture_buffer

    after ->
      nock.cleanAll()

    beforeEach ->
      nock('https://scraperwiki.com')
      .get("/froth/check_key/")
      .reply 403, "403", { 'content-type': 'text/plain' }
      nock('https://scraperwiki.com')
      .get("/froth/check_key/#{apikey}")
      .reply 200, "200", { 'content-type': 'text/plain' }

    it "errors if no API key specified", (done) ->
      opt = _.clone options
      opt.form = _.clone opt.form
      opt.form.apikey = null
      request.get opt, (err, response, body) ->
        response.statusCode.should.equal 403
        (_.isEqual (JSON.parse response.body),
          {error:"Unauthorised"}).should.be.true
        done()

    describe "when a valid API key is supplied", ->
      response = null

      before (done) ->
        request.get options, (err, resp, body) ->
          response = resp
          done()

      it "should read the scraperwiki.json file", ->
        read_stub.calledOnce.should.be.true

      it "returns a valid JSON settings object", ->
        response.statusCode.should.equal 200
        settings = JSON.parse response.body
        should.exist settings
        settings.database.should.equal 'sqlite.db'

  describe "POST /<box_name>/settings", ->
    it "gives errors for bad JSON"
    it "succeeds with good JSON"
    it "saves the scraperwiki.json"
