# basic.coffee

http = require 'http'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000/'

describe 'server', ->
  before (done) ->
    server = require 'serv'
    done()

  it 'can be started', (done) ->
    http.get httpopts, (err, res) ->
      done()

  it 'gives an error when creating a databox without a key', (done) ->
    u = baseurl + 'newdatabox'
    request.post {url:u}, (err, resp, body) ->
      resp.statusCode.should.equal 403
      resp.body.should.equal '{ "error": "No API key supplied" }'
      done()

  it "doesn't give an error when creating a databox without a key", (done) ->
    options =
      uri: baseurl + 'newdatabox'
      form:
        apikey: 'blah'

    request.post options, (err, resp, body) ->
        resp.statusCode.should.equal 200
        done()

  it "returns an error when the apikey is invalid"
  it "doesn't return an error when the apikey is valid"
