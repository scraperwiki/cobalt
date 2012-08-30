# cobalt.coffee

exec = (require 'child_process').exec
fs = require 'fs'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
_ = require 'underscore'

host = 'boxecutor-int-test-0.scraperwiki.net'
baseurl = "http://#{host}/"

cobalt_api_key = process.env.COBALT_API_KEY
boxname = 'cotest/' + String(Math.random()).replace(/\./,'')

describe 'Integration testing', ->
  describe 'When I use the http API', ->
    it 'GET / works'
    it 'I can create a box', (done) ->
      should.exist cobalt_api_key
      options =
        uri: "http://#{host}/#{boxname}"
        form:
          apikey: cobalt_api_key
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.should.have.status 200
        done()

    it 'I can add an ssh key', (done) ->
      options =
        uri: "http://#{host}/#{boxname}/sshkeys"
        form:
          apikey: cobalt_api_key
          sshkey: fs.readFileSync "../swops-secret/cotest-rsa.pub", "ascii"
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.should.have.status 200
        done()
      
    it 'the CORS headers are present'
  describe 'When I login to my box', ->
    it 'SSH works', (done) ->
      cmd = "ssh testorg/newbox@#{host} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o PreferredAuthentications=publickey 'exit 99'"
      exec cmd, (err, stdout_, stderr_) ->
          console.log err
          err.code.should.equal 99
          done()

    it 'I can see my readme.md'
    it 'I can see my git repo'
    it 'I cannot see any other box'
  describe 'When I publish some files', ->
    it 'I can see a root index page'
    it 'I can see normal files'
    it 'I can see an index page for subdirectories'
    it 'I can follow my own symlinks'
    it 'I cannot follow naughty symlinks'
    describe 'as JSONP', ->
      it 'the JSONP thing works'
    describe 'as JSON', ->
      it 'the CORS headers are still present'
  describe 'When I get data', ->
    it 'I can use the SQL web API'
   
