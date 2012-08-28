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
      fixture_buffer = fs.readFileSync "test/fixtures/scraperwiki.json", 'utf8'

      read_stub = sinon.stub(fs, 'readFile')
        .withArgs('/home/newdatabox/scraperwiki.json')
        .callsArgWith(2, null, fixture_buffer)

    after ->
      nock.cleanAll()
      fs.readFile.restore()

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
    response = null
    write_stub = null
    options = null
    apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

    before ->
      options =
          uri: baseurl + 'newdatabox/settings/'
          form:
            apikey: apikey

      write_stub = sinon.stub(fs, 'writeFile')
        .withArgs('/home/newdatabox/scraperwiki.json')
        .callsArgWith(3, null)

    after ->
      nock.cleanAll()
      fs.writeFile.restore()

    describe 'when the JSON is ok', ->
      before (done) ->
        nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options.form.data = JSON.stringify {database: 'sqlite.db'}
        request.post options, (err, resp, body) ->
          response = resp
          done()

      it "returns ok", ->
        response.statusCode.should.equal 200

      it "saves the scraperwiki.json", ->
        write_stub.calledOnce.should.be.true

    describe 'when the JSON invalid', ->
      before (done) ->
        nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options.form.data = "#why no comments? {asfsdf:'sdfsdf'}"
        request.post options, (err, resp, body) ->
          response = resp
          done()

      it "returns an error", ->
        response.statusCode.should.equal 400
