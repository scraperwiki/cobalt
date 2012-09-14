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

ssh_args = [
  "-o User=#{boxname}",
  "-o LogLevel=ERROR",
  "-o UserKnownHostsFile=/dev/null",
  "-o StrictHostKeyChecking=no",
  "-o IdentitiesOnly=yes",
  "-o PreferredAuthentications=publickey",
  "-i #{sshkey_prv_path}"
]

ssh_cmd = (cmd, callback) ->
  ssh = "ssh #{ssh_args.join ' '} #{host} '#{cmd}'"
  exec ssh, (err, stdout, stderr) ->
   callback err, stdout, stderr

scp_cmd = (file_path, file_name, callback) ->
  scp = "scp #{ssh_args.join ' '} #{file_path} #{host}:#{file_name}"
  exec scp, (err, stdout, stderr) ->
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

    it 'I have some default values in scraperwiki.json', (done) ->
      ssh_cmd "cat ~/scraperwiki.json", (err, stdout, stderr) ->
        settings = JSON.parse(stdout)
        settings.database.should.equal "scraperwiki.sqlite"
        settings.publish_token.should.match /[0-9a-z]{15}/
        done()

    it 'I can see my README.md'
    it 'I can see my git repo'
    it 'I cannot see any other box'

  describe 'When I publish some files', ->
    before (done) ->
      scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", ->
        ssh_cmd "echo -n Testing > http/index.html", done

    it 'I can see a root index page', (done) ->
      response = request.get "#{baseurl}/#{boxname}/http/", (err, resp, body) ->
        resp.should.have.status 200
        body.should.equal 'Testing'
        done()

    describe 'with a publishing token set in scraperwiki.json', ->
      it "doesn't allow access if wrong", (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-publishtoken.json", "scraperwiki.json", ->
          response = request.get "#{baseurl}/#{boxname}/0987654321/http/", (err, resp, body) ->
            resp.should.have.status 403
            done()

      it "allows access with it", (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-publishtoken.json", "scraperwiki.json", ->
          response = request.get "#{baseurl}/#{boxname}/0123456789/http/", (err, resp, body) ->
            resp.should.have.status 200
            body.should.equal 'Testing'
            done()

    describe 'without a publishing token set in scraperwiki.json', ->
      it "404s if a token is used", (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", ->
          response = request.get "#{baseurl}/#{boxname}/0987654321/http/", (err, resp, body) ->
            resp.should.have.status 404
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

    describe 'When I specify a callback parameter', (done) ->
      resp = null
      body = null
      before (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "http/test.json", ->
          options =
            uri: "http://#{host}/#{boxname}/http/test.json"
            qs:
              callback: "cb_test"
          request.get options, (err, response, body) ->
            should.not.exist err
            resp = response
            done()

      it 'returns the expected JSON wrapped in the expected callback', ->
        expected = JSON.parse fs.readFileSync "./integration_test/fixtures/scraperwiki-database.json", 'ascii'
        cb_test = (json) -> return json
        a = JSON.stringify(eval resp.body)
        b = JSON.stringify(expected)
        a.should.equal(b)
        resp.should.have.status 200

      it 'does not return JSONP if the requested file is not JSON'

    describe 'as JSON', ->
      it 'the CORS headers are still present'

  describe 'When I use the SQL web API', ->
    resp = null
    before (done) ->
      scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", ->
        ssh_cmd '''echo "create table swdata (num int); insert into swdata values (7);" | sqlite3 test.sqlite''', ->
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
