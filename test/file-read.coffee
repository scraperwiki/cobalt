#fs     = require 'fs'
#child_process = require 'child_process'
#
#request = require 'request'
#should = require 'should'
#sinon  = require 'sinon'
#nock   = require 'nock'
#_ = require 'underscore'
#
#User = require 'models/user'
#Box = require 'models/box'
#SSHKey = require 'models/ssh_key'
#
#nocks = require '../test/nocks'
#
#baseurl = 'http://127.0.0.1:3000/'
#
#describe "Read-only file API", ->
#  server = require 'serv'
#  mongoose = require 'mongoose'
#  apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"
#  User.collection.drop()
#  Box.collection.drop()
#
#  after ->
#    nock.cleanAll()
#
#  describe "GET /<org>/<project>/files/", ->
#    response = null
#    options =
#        uri: baseurl + 'kiteorg/newdatabox/files/'
#        qs:
#          apikey: apikey
#
#    before (done) ->
#      nocks.success apikey
#      read_stub = sinon.stub(child_process, 'spawn')
#        .withArgs('su', ["-c", "cat '/home/'", "kiteorg/newdatabox"])
#      request.get options, (err, resp, body) ->
#        response = resp
#        done()
#
#    after ->
#      child_process.spawn.restore()
#
#    it "should return an error", ->
#      response.should.have.status 500
#
#
#  describe "GET /<org>/<project>/files/README.md", ->
#    read_stub = null
#    response = null
#    apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"
#    options =
#        uri: baseurl + 'kiteorg/newdatabox/files/README.md'
#        qs:
#          apikey: apikey
#
#    before (done) ->
#      nocks.success apikey
#      fixture_buffer = fs.readFileSync "test/fixtures/README.md", 'utf8'
#
#      read_stub = sinon.stub(child_process, 'spawn')
#        .withArgs('su', ["-c", "cat '/home/README.md'", "kiteorg/newdatabox"])
#
#      request.get options, (err, resp, body) ->
#        response = resp
#        done()
#
#    after ->
#      child_process.spawn.restore()
#
#    it "should call cat on README.md", ->
#      read_stub.calledOnce.should.be.true
#
#    xit "should return the contents of README.md", ->
#      response.body.should.match /Test README/
#      response.should.have.status 200
#
#
