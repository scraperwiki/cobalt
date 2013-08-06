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

User = require 'models/user'
Box = require 'models/box'

BASE_URL = 'http://127.0.0.1:3000'
apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"

describe 'the exec endpoint', ->

  before (done) ->
    delete require.cache.server
    @server = require 'server'
    mongoose = require 'mongoose'

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
      done(err)

  it 'returns a 200 when called at an appropriate frequency', (done) ->
    theboxname = "newdatabox" # (stolen from add_sshkeys test)
    options =
      uri: "#{BASE_URL}/#{theboxname}/exec"
      pool: false
      form:
        apikey: apikey
        cmd: 'echo hi. This is a test string of no relevance.'

    request.post options, (err, response, body) ->
      response.statusCode.should.equal 200 
      done()

  it 'correctly throttles frequent calls'
    
