assert = require 'assert'

async = require 'async'
# http://nodejs.org/api/child_process.html
child_process = require 'child_process'

# https://github.com/mikeal/request
request = require 'request'

# https://github.com/visionmedia/should.js/
should = require 'should'
# http://sinonjs.org/docs/
sinon  = require 'sinon'
# http://underscorejs.org/
_ = require 'underscore'

# Local
User = require 'models/user'
Box = require 'models/box'

BASE_URL = 'http://127.0.0.1:3000'
apikey = "342709d1-45b0-4d2e-ad66-6fb81d10e34e"
THROTTLE_PERIOD = 1000
EPSILON = 100

describe 'the exec endpoint', ->

  before (done) ->
    delete require.cache.server
    @server = require 'server'
    mongoose = require 'mongoose'

    @origSpawn = child_process.spawn
    sinon.stub child_process, 'spawn', (cmd, argList) =>
      assert.equal cmd, 'su'
      assert.equal argList[0], '-'
      assert.equal argList[1], '-c'
      # modify command to be a "sh -c" instead of "su - c"
      argList.shift()
      cmd = 'sh'
      return @origSpawn cmd, argList

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

  oneGoodExec = (done) ->
    theboxname = "newdatabox" # (stolen from add_sshkeys test)
    options =
      uri: "#{BASE_URL}/#{theboxname}/exec"
      pool: false
      form:
        apikey: apikey
        cmd: 'sleep 0.1'

    request.post options, (err, response, body) ->
      if err
        return done err, null
      done err, response.statusCode
  MAX_ALLOWED_IN_FLIGHT = 5
  it 'returns a 200 when called at an appropriate frequency', (done) ->
    async.mapLimit [1..9], MAX_ALLOWED_IN_FLIGHT, (item, cb) ->
      oneGoodExec cb
    , (err, results) ->
      assert _.every results, (statusCode) -> statusCode == 200
      done()

  it 'returns a 429 when requests are made too frequently', (done) ->
    async.mapLimit [1..9], MAX_ALLOWED_IN_FLIGHT + 1, (item, cb) ->
      oneGoodExec cb
    , (err, results) ->
      assert 200 in results
      assert 429 in results
      done()
