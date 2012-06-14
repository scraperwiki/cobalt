# basic.coffee

http = require 'http'

describe 'server', ->
  before (done) ->
    server = require 'serv'
    done()
  it 'can be started', (done) ->
    http.get {host:'127.0.0.1', port:3000, path:'/'}, (err, res) ->
      done()
