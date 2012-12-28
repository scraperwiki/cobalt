# cobalt.coffee

{exec} = require 'child_process'
fs = require 'fs'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
_ = require 'underscore'

host = process.env.COBALT_INTEGRATION_TEST_SERVER or 'boxecutor-int-test-0.scraperwiki.net'
baseurl = "http://#{host}"

cobalt_api_key = process.env.COTEST_USER_API_KEY
staff_api_key = process.env.COTEST_STAFF_API_KEY
boxname = 'cotest.' + String(Math.random()).replace(/\./,'')
fresh_username = ->
  'nu' + String(Math.random()).replace(/\./,'')
ssh_boxname = boxname
sshkey_pub_path =  "../swops-secret/cotest-rsa.pub"
sshkey_prv_path =  "../swops-secret/cotest-rsa"
sshkey_prv_path_root = "../swops-secret/id_dsa"
fs.chmodSync sshkey_prv_path, 0o600
fs.chmodSync sshkey_prv_path_root, 0o600

ssh_args = [
  "-o LogLevel=ERROR",
  "-o UserKnownHostsFile=/dev/null",
  "-o StrictHostKeyChecking=no",
  "-o IdentitiesOnly=yes",
  "-o PreferredAuthentications=publickey",
]

ssh_root_args = [ "-o User=root", "-i #{sshkey_prv_path_root}" ].concat(ssh_args)

ssh_user_args = [ "-o User=#{ssh_boxname}", "-i #{sshkey_prv_path}" ].concat(ssh_args)

ssh_cmd = (cmd, callback) ->
  ssh = "ssh #{ssh_user_args.join ' '} #{host} '#{cmd}'"
  exec ssh, (err, stdout, stderr) ->
   callback err, stdout, stderr

ssh_cmd_root = (cmd, callback) ->
  ssh = "ssh #{ssh_root_args.join ' '} #{host} '#{cmd}'"
  exec ssh, (err, stdout, stderr) ->
   callback err, stdout, stderr

scp_cmd = (file_path, file_name, callback) ->
  scp = "scp #{ssh_user_args.join ' '} #{file_path} #{host}:#{file_name}"
  exec scp, (err, stdout, stderr) ->
    callback err, stdout, stderr

describe 'Integration testing', ->
  describe 'When I use the http API', ->
    newuser = null
    newapikey = null
    it 'GET / works', (done) ->
      request.get "#{baseurl}/", (err, resp, body) ->
        resp.should.have.status 200
        done()

    it 'ScraperWiki staff can create a user', (done) ->
      should.exist staff_api_key
      newuser = fresh_username()
      options =
        uri: "http://#{host}/#{newuser}"
        form:
          apikey: staff_api_key
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.statusCode.should.match /^2/
        json = JSON.parse body
        newuser.should.equal json.shortname
        should.exist json.apikey
        newapikey = json.apikey
        done()

    xit 'The new user can see their details', (done) ->
      should.exist newuser
      should.exist newapikey
      options =
        uri: "http://#{host}/#{newuser}/"
        qs:
          apikey: newapikey
      request.get options, (err, resp, body) ->
        should.not.exist err
        resp.statusCode.should.match /^2/
        json = JSON.parse body
        newuser.should.equal json.shortname
        newapikey.should.equal json.apikey
        done()

    it 'The new user can create a box', (done) ->
      myfirstbox = String(Math.random()).replace('0.','')
      options =
        uri: "http://#{host}/box/#{myfirstbox}"
        form:
          apikey: newapikey
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.statusCode.should.match /^2/
        done()

    it 'I cannot create a user', (done) ->
      should.exist cobalt_api_key
      options =
        uri: "http://#{host}/#{fresh_username()}"
        form:
          apikey: cobalt_api_key
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.should.have.status 403
        done()

    it 'Nobodies cannot create a user', (done) ->
      options =
        uri: "http://#{host}/#{fresh_username()}"
        form:
          apikey: '' + Math.random()
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.should.have.status 403
        done()

    it 'I can create a box', (done) ->
      should.exist cobalt_api_key
      options =
        uri: "http://#{host}/box/#{boxname}"
        form:
          apikey: cobalt_api_key
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.statusCode.should.match /^2/
        done()

    it 'I can add an ssh key', (done) ->
      options =
        uri: "http://#{host}/#{boxname}/sshkeys"
        form:
          apikey: cobalt_api_key
          sshkey: fs.readFileSync sshkey_pub_path, "ascii"
      request.post options, (err, resp, body) ->
        should.not.exist err
        resp.statusCode.should.match /^2/
        done()

    it 'the CORS headers are present', (done) ->
      request.get "#{baseurl}/", (err, resp, body) ->
        resp.statusCode.should.match /^2/
        resp.headers["access-control-allow-origin"].should.equal '*'
        done()

  describe 'When I login to my box', ->
    it 'SSH works', (done) ->
      ssh_cmd 'exit 99', (err) ->
        err.code.should.equal 99
        done()

    it 'SFTP works', (done) ->
      ssh = "echo ls | sftp  #{ssh_user_args.join ' '} #{host}"
      exec ssh, (err, stdout, stderr) ->
        should.not.exist err
        done()

    it 'I have some default values in scraperwiki.json', (done) ->
      ssh_cmd "cat ~/scraperwiki.json", (err, stdout, stderr) ->
        settings = JSON.parse(stdout)
        settings.database.should.equal "scraperwiki.sqlite"
        settings.publish_token.should.match /[0-9a-z]{15}/
        done()

    it 'I have a README.md with the box URL in', (done) ->
      ssh_cmd "cat ~/README.md", (err, stdout, stderr) ->
        should.not.exist err
        stderr.should.be.empty
        stdout.should.include "https://box.scraperwiki.com/#{boxname}"
        done()

    it 'I have a git repo with a default .gitignore and initial commit', (done) ->
      ssh_cmd "git log", (err, stdout, stderr) ->
        should.not.exist err
        stderr.should.be.empty
        ssh_cmd "git show README.md .gitignore", (err, stdout, stderr) ->
          should.not.exist err
          stderr.should.be.empty
          done()

    it "I cannot see any other box (i.e. I'm chrooted)", (done) ->
      ssh_cmd "ls -di", (err, stdout, stderr) ->
        should.not.exist err
        stdout.should.not.match /2 \//
        done()

  describe 'When I publish some files', ->
    before (done) ->
      scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", ->
        ssh_cmd "echo -n Testing > http/index.html", done

    describe "...HTTP...", ->
      it 'I can see a root index page', (done) ->
        request.get "#{baseurl}/#{boxname}/http/", (err, resp, body) ->
          resp.should.have.status 200
          body.should.equal 'Testing'
          done()

      it 'I can see normal files', (done) ->
          request.get "#{baseurl}/#{boxname}/http/index.html", (err, resp, body) ->
            resp.should.have.status 200
            body.should.equal 'Testing'
            done()

      it 'I can see an index page for subdirectories', (jai_fini) ->
        ssh_cmd "mkdir /home/http/shakeit", ->
          request.get "#{baseurl}/#{boxname}/http/shakeit", (err, resp, body) ->
            resp.should.have.status 200
            body.should.include 'Index of'
            jai_fini()

      describe 'with a publishing token set in scraperwiki.json', ->
        it "doesn't allow access if wrong", (done) ->
          scp_cmd "./integration_test/fixtures/scraperwiki-publishtoken.json", "scraperwiki.json", ->
            request.get "#{baseurl}/#{boxname}/0987654321/http/", (err, resp, body) ->
              resp.should.have.status 403
              done()

        it "allows access with it", (done) ->
          scp_cmd "./integration_test/fixtures/scraperwiki-publishtoken.json", "scraperwiki.json", ->
            request.get "#{baseurl}/#{boxname}/0123456789/http/", (err, resp, body) ->
              resp.should.have.status 200
              body.should.equal 'Testing'
              done()

        it 'I am redirected for legacy URLs with / in box name', (done) ->
            legacy_boxname = boxname.replace('.', '/')
            request.get
              uri: "#{baseurl}/#{legacy_boxname}/0123456789/http/index.html"
              followRedirect:false
              , (err, resp, body) ->
                resp.should.have.status 301
                done()

      describe 'without a publishing token set in scraperwiki.json', ->
        it "404s if a token is used", (done) ->
          scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", ->
            request.get "#{baseurl}/#{boxname}/0987654321/http/", (err, resp, body) ->
              resp.should.have.status 404
              done()

    describe "...files API...", ->
      it 'I can see my README.md file using the files API', (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/files/README.md"
            qs:
              apikey: cobalt_api_key
        request.get options, (err, resp, body) ->
          body.should.include "# ScraperWiki Box: #{boxname} #"
          resp.should.have.status 200
          done()

      it 'I can see my index.html file using the files API', (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/files/http/index.html"
            qs:
              apikey: cobalt_api_key
        request.get options, (err, resp, body) ->
          body.should.equal 'Testing'
          resp.should.have.status 200
          done()

    describe "...exec API...", ->
      it 'I can cat my README.md', (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/exec"
            form:
              apikey: cobalt_api_key
              cmd: "cat ~/README.md"
        request.post options, (err, resp, body) ->
          body.should.include "# ScraperWiki Box: #{boxname} #"
          resp.should.have.status 200
          done()

      it 'I can write to a file', (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/exec"
            form:
              apikey: cobalt_api_key
              cmd: "echo foo > ~/bar"
        request.post options, (err, resp, body) ->
          resp.should.have.status 200

          ssh_cmd "cat ~/bar | sed s/foo/foobar/g", (err, stdout, stderr) ->
            stdout.should.include 'foobar'
            done()

      it "I can't break the chroot", (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/exec"
            form:
              apikey: cobalt_api_key
              cmd: "ls -di /;'ls -di /;''"
        request.post options, (err, resp, body) ->
          resp.should.have.status 200
          body.should.not.include '2 /'
          done()

      it "I can be sure that my process is killed after I disconnect", (done) ->
        options =
            uri: "#{baseurl}/#{boxname}/exec"
            timeout: 1000
            form:
              apikey: cobalt_api_key
              cmd: "tail -f /dev/urandom"
        request.post options, (err, resp, body) ->
          ssh_cmd "ps aux", (err, stdout, stderr) ->
            stdout.should.not.include 'urandom'
            done()



    describe '...symlinks...', ->
      before (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", ->
          ssh_cmd "ln -s /etc/shadow ~/http/nawty; ln -s ../scraperwiki.json ~/http/nice ", done

      it 'I can follow my own symlinks', (done) ->
        request.get "#{baseurl}/#{boxname}/http/nice", (err, resp, body) ->
          expected = fs.readFileSync "./integration_test/fixtures/scraperwiki-database.json", 'ascii'
          resp.should.have.status 200
          body.should.equal expected
          done()

      it 'I cannot follow naughty symlinks', (done) ->
        request.get "#{baseurl}/#{boxname}/http/nawty", (err, resp, body) ->
          resp.should.have.status 403
          body.should.include 'Forbidden'
          done()

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
        # With the current jsonp hack, this test will fail

  describe 'When I use the SQL web API', ->
    resp = null
    options =
      qs:
        q: "select num*num from swdata"

    before (done) ->
      ssh_cmd '''echo "create table swdata (num int); insert into swdata values (7);" | sqlite3 test.sqlite''', done

    describe 'with a publishing token set in scraperwiki.json', ->
      before (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-publishtoken.json", "scraperwiki.json", done

      describe 'when wrong', ->
        before (done) ->
          request.get { uri: "#{baseurl}/#{boxname}/0987654321/sqlite/", qs: options.qs }, (err, r, body) ->
            resp = r
            done()

        it "doesn't allow access", ->
          resp.should.have.status 403

      describe 'when correct', ->
        before (done) ->
          request.get { uri: "#{baseurl}/#{boxname}/0123456789/sqlite/", qs: options.qs }, (err, r, body) ->
            resp = r
            done()

        it "allows access", ->
          resp.should.have.status 200

        it 'returns JSON', ->
          should.exist (JSON.parse resp.body)

        it 'has value 49', ->
          (JSON.parse resp.body)[0]['num*num'].should.equal 49

      it 'redirected for legacy URLs with / in box name', (done) ->
          legacy_boxname = boxname.replace('.', '/')
          request.get
            uri: "#{baseurl}/#{legacy_boxname}/0123456789/sqlite/"
            qs: options.qs
            followRedirect:false
            , (err, resp, body) ->
              resp.should.have.status 301
              done()


    describe 'without a publishing token set in scraperwiki.json', ->
      before (done) ->
        scp_cmd "./integration_test/fixtures/scraperwiki-database.json", "scraperwiki.json", done

      it "404s if a token is used", (done) ->
        request.get { uri: "#{baseurl}/#{boxname}/0123456789/sqlite/", qs: options.qs }, (err, r, body) ->
          r.should.have.status 404
          done()

      it "allows access", (done) ->
        request.get { uri: "#{baseurl}/#{boxname}/sqlite/", qs: options.qs }, (err, r, body) ->
          r.should.have.status 200
          done()
      it "does JSONP", (done) ->
        qs = { q: options.qs.q, callback: 'ploq' }
        request.get { uri: "#{baseurl}/#{boxname}/sqlite/", qs: qs }, (err, r, body) ->
          r.should.have.status 200
          should.exist body.match(/^ploq\(/)
          done()


  describe 'When Cobalt has started', ->
    before (done) ->
      ssh_cmd_root "service cobalt stop && rm -f /var/run/cobalt.socket && service cobalt start && sleep 2", done

    describe "the created unix socket", ->

      it "is listened to by Cobalt", (done) ->
        ssh_cmd_root "netstat -a | grep cobalt", (err, stdout, stderr) ->
          stdout.should.include "/var/run/cobalt.socket"
          done()

      it "has the right permissions", (done) ->
        ssh_cmd_root "stat -c \"%U %a\" /var/run/cobalt.socket", (err, stdout, stderr) ->
          stdout.should.equal "www-data 600\n"
          done()
