# box_upload.coffee

child_process = require 'child_process'
fs     = require 'fs'
http = require 'http'

# https://github.com/flatiron/nock
nock   = require 'nock'
# https://github.com/mikeal/request
request = require 'request'
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
SSHKey = require 'models/ssh_key'

nocks = require '../test/nocks'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
BASE_URL = 'http://127.0.0.1:3000'
apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

describe 'Upload file to box', ->
  after ->
    nock.cleanAll()

  describe '( POST /<boxname>/file/ )', ->
    server = null
    mongoose = null
    write_stub = null
    chmod_stub = null
    URL = "#{BASE_URL}/newdatabox/file/"
 
    before (done) ->
      server = require 'serv'
      mongoose = require 'mongoose'

      # write_stub = sinon.stub(fs, 'writeFileSync').withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys"
      # chmod_stub = sinon.stub(fs, 'chmodSync').withArgs "/opt/cobalt/etc/sshkeys/newdatabox/authorized_keys", (parseInt '0600', 8)
      # chown_stub = sinon.stub(child_process, 'exec').withArgs("chown newdatabox: /opt/cobalt/etc/sshkeys/newdatabox/authorized_keys").callsArg(1)

      # TODO: icky, we want fixtures or mocking
      User.collection.drop ->
        Box.collection.drop ->
          new User({apikey: apikey, shortname: 'kiteorg'}).save ->
            User.findOne {apikey: apikey}, (err, user) ->
              new Box({user: user._id, name: 'newdatabox'}).save ->
                SSHKey.collection.drop ->
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
      form.pipe request
      request.on 'response', (resp) ->
        resp.statusCode.should.equal 403
        done()

    describe 'when the API key is valid', ->
      before ->
        @exec_stub = sinon.stub(child_process, 'exec').callsArg(1)
        sinon.stub(fs, 'existsSync').returns(true)
        sinon.stub(fs, 'statSync').returns(isDirectory: -> true)

      before (done) ->
        form = new FormData()
        form.append('file', fs.createReadStream("test/box_upload.coffee"))
        form.append("randomkey", "randomvalue")
        form.append("apikey", apikey)
        headers = form.getHeaders()
        # mikeal's request overwrites headers (if form is
        # specified), so we have to use plain-old http.request.
        request = http.request
          method: 'post'
          host: "localhost"
          port: 3000
          path: "/newdatabox/file/"
          headers: headers
        form.pipe request
        request.on 'response', (resp) =>
          @resp = resp
          done()

      it "has OK status", ->
        @resp.statusCode.should.equal 200

      it "uploads file to box's incoming directory", ->
        (@exec_stub.calledWithMatch /mv.*newdatabox/).should.be.true
        
      it "chowns the file", ->
        (@exec_stub.calledWithMatch /chown.*newdatabox/).should.be.true
