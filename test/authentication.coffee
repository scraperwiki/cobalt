request = require 'request'
should = require 'should'

User = require 'models/user'

BASEURL = "http://127.0.0.1:3000"

# TODO: move authentication to custard, IMHO cobalt's only concept of
# a user should be her apikey and 'shortname'
describe 'Authentication', ->
  context 'user exists', ->
    shortname = 'kiteorg'
    apikey = String(Math.random())
    password = String(Math.random())
    displayname = 'Robot Hat'
    response = null

    before (done) ->
      server = require 'serv'
      User.collection.drop ->
        # Create user with password (by faking it),
        fields =
                 shortname: shortname
                 apikey: apikey
                 displayname: displayname

        new User(fields).save ->
          User.findOne {apikey: apikey}, (err, user) ->
            console.warn err if err?
            user.setPassword password, done

    context 'password is right', ->
      before (done) ->
        # Use the user's auth endpoint.
        options =
          uri: "#{BASEURL}/#{shortname}/auth"
          form:
            password: password
        request.post options, (err, resp, body) ->
          response = resp
          done()

      it 'returns a status code of 200', ->
        response.should.have.status 200

      it 'returns the apikey and shortname', ->
        obj = JSON.parse response.body
        should.exist obj.apikey
        obj.apikey.length.should.be.above 1
        should.exist obj.shortname
        obj.shortname.length.should.be.above 1
        should.exist obj.displayname
        obj.displayname.length.should.be.above 1

      it 'should not contain a password field', ->
        obj = JSON.parse response.body
        should.not.exist obj.password

    context 'password is wrong', ->
      before (done) ->
        # Use the user's auth endpoint.
        options =
          uri: "#{BASEURL}/#{shortname}/auth"
          form:
            password: 'marmothat'
        request.post options, (err, resp, body) ->
          response = resp
          done()

      it 'returns a status code of 403', ->
        response.should.have.status 403

      it 'returns an error object', ->
        obj = JSON.parse response.body
        should.exist obj.error

  context 'user does not exist', ->
    response = null
    before (done) ->
      options =
        uri: "#{BASEURL}/flibberty/auth"
      request.post options, (err, resp, body) ->
        response = resp
        done()

    it 'responds with a 403', ->
      response.should.have.status 403
