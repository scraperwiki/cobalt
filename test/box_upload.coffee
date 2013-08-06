# box_upload.coffee

child_process = require 'child_process'
fs     = require 'fs'
http = require 'http'

# https://github.com/felixge/node-form-data
FormData = require 'form-data'
# https://github.com/visionmedia/should.js/
should = require 'should'
# http://sinonjs.org/docs/
sinon  = require 'sinon'
# http://underscorejs.org/
_ = require 'underscore'

User = require 'models/user'
Box = require 'models/box'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
BASE_URL = 'http://127.0.0.1:3000'
apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

describe 'Upload file to box', ->
  describe '( POST /<boxname>/file/ )', ->
    server = null
    mongoose = null
    write_stub = null
    chmod_stub = null
    URL = "#{BASE_URL}/newdatabox/file/"

    before (done) ->
      delete require.cache.server
      @server = require 'server'
      mongoose = require 'mongoose'

      # write_stub = sinon.stub(fs, 'writeFileSync').withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys"
      # chmod_stub = sinon.stub(fs, 'chmodSync').withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys", (parseInt '0600', 8)
      # chown_stub = sinon.stub(child_process, 'exec').withArgs("chown newdatabox: /opt/cobalt/etc/sshkeys/newdatabox/authorized_keys").callsArg(1)

      # TODO: icky, we want fixtures or mocking
      User.collection.drop =>
        Box.collection.drop =>
          new User({apikey: apikey, shortName: 'kiteorg'}).save =>
            User.findOne {apikey: apikey}, (err, user) =>
              new Box({users: ['kiteorg'], name: 'newdatabox'}).save =>
                @server.start (err) ->
                  done(err)

    after (done) ->
      @server.stop (err) ->
        done()

    it 'returns an error when posting files without an API key', (done) ->
      form = new FormData()
      form.append('file', fs.createReadStream("test/box_upload.coffee"))
      form.append("randomkey", "randomvalue")
      form.append("apikey", "notanapikey")
      headers = form.getHeaders()
      # mikeal's request overwrites headers (if form is
      # specified), so we have to use plain-old http.request.
      request = http.request
        method: 'post'
        host: "localhost"
        port: 3000
        path: "/newdatabox/file/"
        headers: headers
        # Avoid http request pooling in order to avoid keeping the server
        # alive, breaking the tests.
        agent: false
      form.pipe request
      request.on 'response', (resp) ->
        resp.statusCode.should.equal 403
        done()

    describe 'when the API key is valid', ->
      before ->
        @exec_stub = sinon.stub(child_process, 'exec').callsArg(1)
        sinon.stub fs, 'stat', (a_, cb) ->
          cb null, isDirectory: -> true

      after ->
        child_process.exec.restore()
        fs.stat.restore()

      before (done) ->
        form = new FormData()
        form.append('file', fs.createReadStream("test/box_upload.coffee"))
        form.append("randomkey", "randomvalue")
        form.append("apikey", apikey)
        form.append("next", "/then")
        headers = form.getHeaders()
        # mikeal's request overwrites headers (if form is
        # specified), so we have to use plain-old http.request.
        request = http.request
          method: 'post'
          host: "localhost"
          port: 3000
          path: "/newdatabox/file/"
          headers: headers
          # Avoid http request pooling in order to avoid keeping the server
          # alive, breaking the tests.
          agent: false
        form.pipe request
        request.on 'response', (resp) =>
          @resp = resp
          done()

      it "redirects", ->
        @resp.statusCode.should.equal 301
        @resp.headers.location.should.match /^.then/

      it "uploads file to box's incoming directory", ->
        (@exec_stub.calledWithMatch /mv.*newdatabox/).should.be.true

      it "chowns the file", ->
        (@exec_stub.calledWithMatch /chown.*newdatabox/).should.be.true
