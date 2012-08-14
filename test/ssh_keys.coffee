# basic.coffee

http = require 'http'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
nock   = require 'nock'
sinon  = require 'sinon'
fs     = require 'fs'
child_process = require 'child_process'
_ = require 'underscore'

mongoose = require 'mongoose'
User = require 'models/user'
Box = require 'models/box'
SSHKey = require 'models/ssh_key'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
BASE_URL = 'http://127.0.0.1:3000/'
apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

describe 'SSH keys:', ->
  describe '( POST /<box_name>/sshkeys )', ->
    server = null
    write_stub = null
    chmod_stub = null
    URL = "#{BASE_URL}newdatabox/sshkeys"

    before (done) ->
      server = require 'serv'
      # TODO: icky, we want fixtures or mocking
      User.collection.drop()
      Box.collection.drop()
      new User({apikey: apikey}).save()
      User.findOne {apikey: apikey}, (err, user) ->
        new Box({user: user._id, name: 'newdatabox'}).save()
        SSHKey.collection.drop()
        done()
      #write_stub = sinon.stub fs, 'writeFile', (_p, _t, _e, cb) -> cb()
      write_stub = sinon.stub(fs, 'writeFileSync').withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys"
      chmod_stub = sinon.stub(fs, 'chmodSync').withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys", (parseInt '0600', 8)
      chown_stub = sinon.stub(child_process, 'exec').withArgs "chown newdatabox: /opt/cobalt/etc/sshkeys/newdatabox/authorized_keys"

    after (done) ->
      mongoose.disconnect ->
        done()

    it 'returns an error when adding ssh keys without an API key', (done) ->
      request.post {url:URL, form: {sshkey: 'x'}}, (err, resp, body) ->
        resp.statusCode.should.equal 403
        (_.isEqual (JSON.parse resp.body), {"error":"No API key supplied"}).should.be.true
        done()

    describe 'when the apikey is valid and box exists', ->
      froth = null
      response = null
      exec_stub = null
      sshkey =
        """
        ssh-dss AAAAB3NzaC1kc3MAAACBAPvBVeF9dMD7HFW5oGxd30JlfmhkAc8/Z+JIYmrZF1vTCpSyByYkDzey9DDR3Etob2YIEL/wn8/EQMCh8hNH96vQSzGqRXVYL37I89YbDWgkXLg9NcdJL7WwsnTioGJSCmc95OPXELREzoqqBL+N43JeVesreKBBJlX7haBdMdBVAAAAFQCVQ3RMcRY6OghLiqSL3sUHYuf8BwAAAIEAz58IebcwRIddJiVGZBpm/+wxErKe+iyz8HWvDc7qHEYTfds9Gpk3DaMjV+aPklataCA+dYY/XTo3NFhm0gt/ENs6FJjYPhKdByFv/iPny8T5C+Fhy1czgb3SdzFpHMK9ICTi/aUSXES/Z8aCsanBTWjlmgc1RgCCxoa+jLoei9AAAACAZYWhPRKTsqZlPncfLlEdFfn9oqHAqd3jVAHjc6f2UFLoPjTlALcdy+cSf/Hp/1Ga8WVBB8Twm0H6hz78EQO6AXf56XagBv7hd4pRetxe8E1OebwbRQkPzuAh4h/rTfK0uLp7koNZLUuH4wfFEkV4pxcoV4XM+9YjoalWKxJEiB4= tlevine@motorsag
        """

      before (done) ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options =
          uri: URL
          form:
            apikey: apikey
            sshkey: sshkey

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it 'requests validation from froth', ->
        froth.isDone().should.be.true

      it "doesn't return an error", ->
        response.statusCode.should.equal 200

      describe 'when sshkey is present', ->
        it 'extracts the name from the key', ->
          SSHKey.extract_name(sshkey).should.equal 'tlevine@motorsag'

        it 'saves the key to the database', (done) ->
          SSHKey.findOne {name: 'tlevine@motorsag'}, (err, key) ->
            should.exist key
            done()

        it "overwrites the box's authorized_keys file with all ssh keys", ->
          write_stub.calledOnce.should.be.true
          chmod_stub.calledOnce.should.be.true

    describe 'when the apikey is invalid', ->
      before ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/junk")
        .reply 403, "403", { 'content-type': 'text/plain' }

      it 'returns an error', (done) ->
        options =
          uri: URL
          form:
            apikey: 'junk'
            sshkey: 'blah'

        request.post options, (err, resp, body) ->
          resp.statusCode.should.equal 403
          (_.isEqual (JSON.parse resp.body), {"error":"Unauthorised"}).should.be.true
          done()

    describe 'when the apikey does not belong to the box creator', ->
      before ->
        apikey2 = 'otheruserapikey'
        new User({apikey: apikey2}).save()

        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/otheruserapikey")
        .reply 200, "200", { 'content-type': 'text/plain' }

      it 'returns an error', (done) ->
        options =
          uri: URL
          form:
            apikey: 'otheruserapikey'
            sshkey: 'blah'

        request.post options, (err, resp, body) ->
          resp.statusCode.should.equal 403
          (_.isEqual (JSON.parse resp.body), {"error":"Unauthorised"}).should.be.true
          done()

    describe "when the box doesn't exist", ->
      response = null
      before (done) ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options =
          uri: URL
          form:
            apikey: apikey
            sshkey: 'is not checked'

        options.uri = options.uri.replace 'newdatabox', 'nodatabox'

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it 'returns an error', (done) ->
          response.statusCode.should.equal 404
          (_.isEqual (JSON.parse response.body), {"error":"Box not found"}).should.be.true
          done()

    describe "when sshkey isn't present", ->
      response = null

      before (done) ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }

        options =
          uri: URL
          form:
            apikey: apikey

        request.post options, (err, resp, body) ->
            response = resp
            done()

      it 'returns an error', ->
        (_.isEqual (JSON.parse response.body), {"error":"SSH Key not specified"}).should.be.true

    describe "when sshkey isn't valid", ->
      before ->
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }
        froth = nock('https://scraperwiki.com')
        .get("/froth/check_key/#{apikey}")
        .reply 200, "200", { 'content-type': 'text/plain' }


      # do we need this now?
      it 'returns an error if completely invalid', (done) ->
        invalid_sshkey = "foo bar baz"
        options =
          uri: URL
          form:
            apikey: apikey
            sshkey: invalid_sshkey
        request.post options, (err, resp, body) ->
          (_.isEqual (JSON.parse resp.body),  {"error":"SSH Key format not valid"}).should.be.true
          done()


      it 'returns an error if no name', (done) ->
        noname_sshkey =
          """
          ssh-dss AAAAB3NzaC1kc3MAAACBAPvBVeF9dMD7HFW5oGxd30JlfmhkAc8/Z+JIYmrZF1vTCpSyByYkDzey9DDR3Etob2YIEL/wn8/EQMCh8hNH96vQSzGqRXVYL37I89YbDWgkXLg9NcdJL7WwsnTioGJSCmc95OPXELREzoqqBL+N43JeVesreKBBJlX7haBdMdBVAAAAFQCVQ3RMcRY6OghLiqSL3sUHYuf8BwAAAIEAz58IebcwRIddJiVGZBpm/+wxErKe+iyz8HWvDc7qHEYTfds9Gpk3DaMjV+aPklataCA+dYY/XTo3NFhm0gt/ENs6FJjYPhKdByFv/iPny8T5C+Fhy1czgb3SdzFpHMK9ICTi/aUSXES/Z8aCsanBTWjlmgc1RgCCxoa+jLoei9AAAACAZYWhPRKTsqZlPncfLlEdFfn9oqHAqd3jVAHjc6f2UFLoPjTlALcdy+cSf/Hp/1Ga8WVBB8Twm0H6hz78EQO6AXf56XagBv7hd4pRetxe8E1OebwbRQkPzuAh4h/rTfK0uLp7koNZLUuH4wfFEkV4pxcoV4XM+9YjoalWKxJEiB4=
          """

        options =
          uri: URL
          form:
            apikey: apikey
            sshkey: noname_sshkey

        request.post options, (err, resp, body) ->
            (_.isEqual (JSON.parse resp.body),  {"error":"SSH Key has no name"}).should.be.true
            done()

