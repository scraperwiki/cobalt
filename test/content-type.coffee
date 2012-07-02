# basic.coffee

http = require 'http'
request = require 'request'
should = require 'should'
nock   = require 'nock'
sinon  = require 'sinon'

mongoose = require 'mongoose'

httpopts = {host:'127.0.0.1', port:3000, path:'/'}
baseurl = 'http://127.0.0.1:3000/'

describe 'Content Types', ->
  describe '( GET /foo )', ->
    server = null

    before (done) ->
      server = require 'serv'
      done()

    it 'has JSON MIME type', (done) ->
      u = baseurl + 'foo'
      request.get {url:u}, (err, resp, body) ->
        resp.headers['content-type'].should.equal 'application/json'
        done()

  describe '( GET / )', ->
    server = null

    before (done) ->
      server = require 'serv'
      done()

    it 'has JSON MIME type', (done) ->
      u = baseurl
      request.get {url:u}, (err, resp, body) ->
        resp.headers['content-type'].should.equal 'application/json'
        done()
