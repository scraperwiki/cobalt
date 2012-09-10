# cobalt.coffee

exec = (require 'child_process').exec
fs = require 'fs'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
_ = require 'underscore'

host = process.env.COBALT_INTEGRATION_TEST_SERVER or 'boxecutor-int-test-0.scraperwiki.net'
baseurl = "http://#{host}"

cobalt_api_key = process.env.COTEST_USER_API_KEY
boxname = 'cotest/' + String(Math.random()).replace(/\./,'')
sshkey_pub_path =  "../swops-secret/cotest-rsa.pub"
sshkey_prv_path =  "../swops-secret/cotest-rsa"
fs.chmodSync sshkey_prv_path, 0o600

ssh_cmd = (cmd, callback) ->
  ssh = "ssh #{boxname}@#{host} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o LogLevel=ERROR -i #{sshkey_prv_path} '#{cmd}'"
  exec ssh, (err, stdout, stderr) ->
    callback err, stdout, stderr

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
          sshkey: fs.readFileSync sshkey_pub_path, "ascii"
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.should.have.status 200
        done()
      
    it 'the CORS headers are present'
  describe 'When I login to my box', ->
    it 'SSH works', (done) ->
      ssh_cmd 'exit 99', (err) ->
        err.code.should.equal 99
        done()

    it 'I can see my README.md'
    it 'I can see my git repo'
    it 'I cannot see any other box'

  describe 'When I publish some files', ->
    before (done) ->
      ssh_cmd "echo -n Testing > http/index.html", ->
        ssh_cmd '''echo -n "{\\"database\\": \\"scraperwiki.sqlite\\"}" > scraperwiki.json''', done

    it 'I can see a root index page', (done) ->
      response = request.get "#{baseurl}/#{boxname}/http/", (err, resp, body) ->
        resp.should.have.status 200
        body.should.equal 'Testing'
        done()

    it 'I can see my my README.md file using the files API', (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/files/README.md"
            qs:
              apikey: cobalt_api_key
        response = request.get options, (err, resp, body) ->
          body.should.match /This is the README\.md file/
          resp.should.have.status 200
          done()

    it 'I can see my my index.html file using the files API', (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/files/http/index.html"
            qs:
              apikey: cobalt_api_key
        response = request.get options, (err, resp, body) ->
          body.should.equal 'Testing'
          resp.should.have.status 200
          done()

    it 'I can see normal files'
    it 'I can see an index page for subdirectories'
    it 'I can follow my own symlinks'
    it 'I cannot follow naughty symlinks'
    describe 'as JSONP', ->
      it 'the JSONP thing works'
    describe 'as JSON', ->
      it 'the CORS headers are still present'
  describe 'When I use the SQL web API', ->
    resp = null
    before (done) ->
       ssh_cmd '''echo "create table swdata (num int); insert into swdata values (7);" |
          sqlite3 scraperwiki.sqlite''', ->
         options =
           uri: "http://#{host}/#{boxname}/sqlite"
           qs:
             q: "select num*num from swdata"
         request.get options, (err, response, body) ->
           should.not.exist err
           resp = response
           done()

    it 'has status 200', ->
      resp.should.have.status 200
    it 'returns JSON', ->
      should.exist (JSON.parse resp.body)
    it 'has value 49', ->
      (JSON.parse resp.body)[0]['num*num'].should.equal 49
