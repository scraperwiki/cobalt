# ssh_keys.coffee

child_process = require 'child_process'
fs     = require 'fs'
http = require 'http'

# https://github.com/mikeal/request
request = require 'request'
# https://github.com/visionmedia/should.js/
should = require 'should'
# http://sinonjs.org/docs/
sinon  = require 'sinon'
# http://underscorejs.org/
_ = require 'underscore'
# https://github.com/scraperwiki/ident-express
# So that it appears in require.cache which we stub.
require 'ident-express'


httpopts = {host:'127.0.0.1', port:3000, path:'/'}
BASE_URL = 'http://127.0.0.1:3000'
apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

# Used as a stub.
existsFake = (path, cb) ->
  res = /newdatabox/.test path
  cb res

checkIdentFake = (req, res, next) ->
  req.ident = 'root'
  next()

describe 'Add SSH keys:', ->
  before ->
    @checkIdentStub = sinon.stub require.cache[require.resolve 'ident-express'],
      'exports',
      checkIdentFake

  describe '( POST /<boxname>/sshkeys )', ->
    server = null
    mongoose = null
    write_stub = null
    chmod_stub = null
    exists_stub = null
    URL = "#{BASE_URL}/newdatabox/sshkeys"

    before (done) ->
      server = require 'serv'
      mongoose = require 'mongoose'

      write_stub = sinon.stub(fs, 'writeFileSync')
        .withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys"
      chmod_stub = sinon.stub(fs, 'chmodSync')
        .withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys", (parseInt '0600', 8)
      chown_stub = sinon.stub(child_process, 'exec')
        .withArgs("chown newdatabox: /opt/cobalt/etc/sshkeys/newdatabox/authorized_keys").callsArg(1)
      exists_stub = sinon.stub fs, 'exists', existsFake
      done()

    after ->
      fs.writeFileSync.restore()
      fs.chmodSync.restore()
      child_process.exec.restore()
      fs.exists.restore()

    describe 'when the box exists', ->
      response = null
      exec_stub = null
      sshkey =
        """
        ssh-dss AAAAB3NzaC1kc3MAAACBAPvBVeF9dMD7HFW5oGxd30JlfmhkAc8/Z+JIYmrZF1vTCpSyByYkDzey9DDR3Etob2YIEL/wn8/EQMCh8hNH96vQSzGqRXVYL37I89YbDWgkXLg9NcdJL7WwsnTioGJSCmc95OPXELREzoqqBL+N43JeVesreKBBJlX7haBdMdBVAAAAFQCVQ3RMcRY6OghLiqSL3sUHYuf8BwAAAIEAz58IebcwRIddJiVGZBpm/+wxErKe+iyz8HWvDc7qHEYTfds9Gpk3DaMjV+aPklataCA+dYY/XTo3NFhm0gt/ENs6FJjYPhKdByFv/iPny8T5C+Fhy1czgb3SdzFpHMK9ICTi/aUSXES/Z8aCsanBTWjlmgc1RgCCxoa+jLoei9AAAACAZYWhPRKTsqZlPncfLlEdFfn9oqHAqd3jVAHjc6f2UFLoPjTlALcdy+cSf/Hp/1Ga8WVBB8Twm0H6hz78EQO6AXf56XagBv7hd4pRetxe8E1OebwbRQkPzuAh4h/rTfK0uLp7koNZLUuH4wfFEkV4pxcoV4XM+9YjoalWKxJEiB4= tlevine@motorsag
        """

      before (done) ->

        options =
          uri: URL
          form:
            keys: JSON.stringify [sshkey]

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it "doesn't return an error", ->
        response.statusCode.should.equal 200

      describe 'when keys are present', ->
        it "overwrites the box's authorized_keys file with all ssh keys", ->
          write_stub.calledOnce.should.be.true
          chmod_stub.calledOnce.should.be.true

    describe "when the box doesn't exist", ->
      response = null
      before (done) ->
        options =
          uri: URL
          form:
            keys: JSON.stringify ['is not checked']

        options.uri = options.uri.replace 'newdatabox', 'nodatabox'

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it 'returns an error', (done) ->
          response.statusCode.should.equal 404
          JSON.parse(response.body).error.should.include "not found"
          done()

    describe "when sshkey isn't present", ->
      response = null

      before (done) ->
        options =
          uri: URL
          form: {}

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it 'returns an error', ->
        JSON.parse(response.body).error.should.include "not specified"
