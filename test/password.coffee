request = require 'request'
should = require 'should'

User = require 'models/user'

BASEURL = "http://127.0.0.1:3000"

describe 'Password', ->
  context 'user exists', ->
    shortname = 'kiteorg'
    apikey = String(Math.random())
    password = String(Math.random())
    response = null
    before (done) ->
      server = require 'serv'
      User.collection.drop ->
        # Create user with password (by faking it),
        new User({shortname:shortname, apikey:apikey}).save ->
          User.findOne {apikey: apikey}, (err, user) ->
            user.setPassword password, ->
              # Use the user's password endpoint.
              options =
                uri: "#{BASEURL}/#{shortname}/password"
              request.get options, (err, resp, body) ->
                response = resp
                done()

    it 'returns the hashed password', ->
      response.should.have.status 200
      json = JSON.parse response.body
      should.exist json.password
      json.password.should.not.include password

  context 'user does not exist', ->
    response = null
    before (done) ->
      options =
        uri: "#{BASEURL}/flibberty/password"
      request.get options, (err, resp, body) ->
        response = resp
        done()

    it 'responds with a 404', ->
      response.should.have.status 404
