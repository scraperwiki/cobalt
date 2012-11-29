#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

fs      = require 'fs'
path    = require 'path'
# Avoids warning.  Remove when we definitely use a node version with
# the "modern" fs.existsSync.
existsSync = fs.existsSync || path.existsSync
child_process = require 'child_process'
os      = require 'os'

express = require 'express'
request = require 'request'
exec    = require('child_process').exec
mongoose = require 'mongoose'

User = require 'models/user'
Box = require 'models/box'
Token = require 'models/token'
SSHKey = require 'models/ssh_key'

app = express()

app.use express.bodyParser()

app.configure 'staging', ->
  app.use express.logger()
  app.use express.errorHandler { dumpExceptions: true, showStack: true}

app.configure 'production', ->
  app.use express.logger()
  app.use express.errorHandler()

mongoose.connect process.env['COBALT_DB']

server_hostname = ''
root_url = ''
port = process.env.COBALT_PORT
app.all "*", (req, res, next) ->
  server_hostname = req.header('host')
  root_url = "http://#{server_hostname}"
  root_url = root_url + ":#{process.env.COBALT_PORT}" unless (port == '8000' || isNaN(parseInt(port)))
  next()

# Templating language
app.set('view engine', 'ejs')

parse_settings = (text) ->
  try
    settings = JSON.parse text
    return false unless typeof(settings) is 'object'
    return settings
  catch e
    return false

box_settings = (user_name, callback) ->
  fs.readFile "/home/#{user_name}/scraperwiki.json", 'utf-8', (err, data) ->
    settings = parse_settings data
    callback 'not json', {} if not settings
    callback null, settings if not err?
    callback err, {} if err?

# Consult mongo database for specified profile.
check_auth = (apikey, profile, callback) ->
  User.findOne {apikey: apikey, shortname: profile}, (err, user) ->
    if user
      callback true
    else
      callback false

# Middleware that checks apikey and issues HTTP status as appropriate.
check_api_key = (req, res, next) ->
  if not req.params.profile?
    req.params.profile = req.params[0]
  res.header('Content-Type', 'application/json')
  apikey = req.body.apikey or req.query.apikey
  if apikey?
    check_auth apikey, req.params.profile, (authorised) ->
      if authorised
        return next()
      else
        return res.send {error: "Unauthorised"}, 403
  else
    return res.send {error: "No API key supplied"}, 403

fresh_apikey = ->
  [Math.random(), Math.random()].join('-')

# GET REQUESTS
# These should all be idempotent, i.e. make no changes to the server.

app.get "/", (req, res) ->
  res.header('Content-Type', 'application/json')
  res.render('index', {rooturl: root_url})

app.get "/:profile/?", check_api_key, (req, res) ->
  User.findOne {shortname: req.params.profile}, (err, profile) ->
    res.json profile.objectify()

# Documentation for SSHing to a box.
app.get "/:profile/:project/?", (req, res) ->
  user_name = req.params.profile + '.' + req.params.project
  box_name = req.params.profile + '/' + req.params.project
  res.header('Content-Type', 'application/json')
  check_auth req.query.apikey, req.params.profile, (authorised) ->
    Box.findOne {name: box_name}, (err, box) ->
      return res.send { error: "Box not found" }, 404 unless box?
      box_settings box_name, (err, settings) ->
        res.render 'box',
          user_name: user_name
          box_name: box_name
          rooturl: root_url
          server_hostname: server_hostname
          publish_token: if authorised and settings.publish_token then settings.publish_token else undefined

# Get file
app.get "/:profile/:project/files/*", check_api_key
app.get "/:profile/:project/files/*", (req, res) ->
  res.removeHeader('Content-Type')
  user_name = req.params.profile + '.' + req.params.project
  box_name = req.params.profile + '/' + req.params.project
  path = req.path.replace "/#{box_name}/files", ''
  path = path.replace /\'/g, ''
  user_name = user_name.replace /\'/g, ''
  su = child_process.spawn "su", ["-c", "cat '/home#{path}'", "#{user_name}"]
  su.stdout.on 'data', (data) ->
      res.write data
  su.stderr.on 'data', (data) ->
      res.send {error:"Error reading #{path}"}, 500
  su.on 'exit', (code) ->
      res.end()

# Exec endpoint - see wiki for note about security
app.post "/:profile/:project/exec/?", check_api_key
app.post "/:profile/:project/exec/?", (req, res) ->
  timelog "got POST exec #{req.params.profile}/#{req.params.project} #{req.body.cmd}"
  res.removeHeader 'Content-Type'
  user_name = req.params.profile + '.' + req.params.project
  cmd = req.body.cmd
  su = child_process.spawn "su", ["-c", "#{cmd}", "#{user_name}"]
  su.stdout.on 'data', (data) ->
    res.write data
  su.stderr.on 'data', (data) ->
    res.write data
  su.on 'exit', (code) ->
    res.end()

  req.on 'end', -> su.kill()
  req.on 'close', -> su.kill()

# POST REQUESTS
# These should make changes somewhere, likely to the mongodb database

timelog = (stuff...) ->
  console.log (new Date()).toISOString(), stuff

# Deal with a token
app.post "/token/:token/?", (req, res) ->
  Token.findOne {token: req.params.token}, (err, token) ->
    if token.shortname? and req.body.password?
      # :todo: has token expired?
      User.findOne {shortname: token.shortname}, (err, user) ->
        if user
          # :todo: token should expire
          user.setPassword req.body.password, ->
            return res.json user.objectify()
        else
          timelog "no User with shortname #{token.shortname} for Token #{token.token}"
          return res.send 404
    else
      return res.send 404

# Create a new profile - staff only
# Don't want to check_api_key because this includes its own staff check
app.post "/:profile/?", (req, res) ->
  timelog "got request create profile #{req.params.profile}"
  # :todo: POST to existing profile should be an edit, and we should check
  # the profile's apikey.
  # What we actually do is only allow creation, using a staff apikey.
  User.findOne {apikey: req.body.apikey}, (err, user) ->
    if not user?.isstaff
      return res.send { error: "Not authorised to create new profile" }, 403
    else
      # :todo: Extract more profile details from query params here.
      new User(
        shortname: req.params.profile
        displayname: req.body.displayname
        email: [req.body.email]
        apikey: fresh_apikey()
      ).save (err) ->
        console.log err
        User.findOne {shortname: req.params.profile}, (err, user) ->
          token = String(Math.random()).replace('0.', '')
          new Token({token: token, shortname: user.shortname}).save (err) ->
            # 201 Created, RFC2616
            userobj = user.objectify()
            userobj.token = token
            return res.json userobj, 201

# Create a box
app.post "/:profile/:project/?", check_api_key, (req, res) ->
  timelog "got request create box #{req.params.profile}/#{req.params.project}"
  res.header('Content-Type', 'application/json')
  user_name = req.params.profile + '.' + req.params.project
  box_name = req.params.profile + '/' + req.params.project
  re = /^[a-zA-Z0-9_+-]+\/[a-zA-Z0-9_+-]+$/
  if not re.test box_name
    return res.send {error:
      "Box name should match the regular expression #{String(re)}"}, 404
  # :todo: eventually users using apikeys from ScraperWiki classic won't be allowed,
  # in which case we won't need to create a User object here.
  new User({apikey: req.body.apikey, shortname: req.params.profile}).save (err) ->
    timelog "created database entity: user #{req.params.profile}/#{req.params.project}"
    User.findOne {apikey: req.body.apikey}, (err, user) ->
      timelog "found user (again) #{req.params.profile}/#{req.params.project}"
      return res.send {error: "User not found" }, 404 unless user?
      Box.findOne {name: box_name}, (err, box) ->
        timelog "checked box existence #{req.params.profile}/#{req.params.project}"
        if box
          return res.send {error: "Box already exists"}
        else
          new Box({user: user._id, name: box_name}).save (err) ->
            timelog "created database entity: box #{req.params.profile}/#{req.params.project}"
            if err
              console.log "Creating box: #{err} "
              return res.send {error: "Unknown error"}
            else
              exports.unix_user_add user_name, (err, stdout, stderr) ->
                timelog "added unix user #{req.params.profile}/#{req.params.project}"
                any_stderr = stderr is not ''
                console.log "Error adding user: #{err} #{stderr}" if err? or any_stderr
                return res.send {error: "Unable to create box"} if err? or any_stderr
                return res.send {status: "ok"}

# Add an SSH key to a box
app.post "/:profile/:project/sshkeys/?", check_api_key, (req, res) ->
  user_name = req.params.profile + '.' + req.params.project
  box_name = req.params.profile + '/' + req.params.project

  res.header('Content-Type', 'application/json')
  unless req.body.sshkey? then return res.send { error: "SSH Key not specified" }, 400

  Box.findOne {name: box_name}, (err, box) ->
    return res.send { error: "Box not found" }, 404 unless box?
    User.findOne {apikey: req.body.apikey}, (err, user) ->
      return res.send { error: "No user is authorised for that apikey" }, 403 unless user?
      return res.send { error: "That user is not authorised to use that apikey" }, 403 unless user._id.toString() == box.user.toString()
      try
        name = SSHKey.extract_name req.body.sshkey
      catch TypeError
        return res.send { error: "SSH Key format not valid" }, 400
      unless name then return res.send { error: "SSH Key has no name" }, 400
      key = new SSHKey
        box: box._id
        name: name
        key: req.body.sshkey

      key.save ->
        SSHKey.find {box: box._id}, (err, sshkeys) ->
          keys_path = "/opt/cobalt/etc/sshkeys/#{user_name}/authorized_keys"

          keys = for key in sshkeys
            "#{key.key}"

          fs.writeFileSync keys_path, keys.join '\n', 'utf8'
          # Note: octal.  This is deliberate.
          fs.chmodSync keys_path, 0o600
          child_process.exec "chown #{user_name}: #{keys_path}", (err, stdout, stderr) -> # insecure
            return res.send {"status": "ok"} unless err
            console.log "ERROR: #{err}, stderr: #{stderr}"
            return res.send {"error": "Internal creation error"}

app.listen port
if existsSync(port) && fs.lstatSync(port).isSocket()
  fs.chmodSync port, 0o600
  child_process.exec "chown www-data #{port}"


exports.unix_user_add = (user_name, callback) ->
  cmd = """
        cd /opt/cobalt &&
        . ./code/box_lib.sh &&
        create_user #{user_name} &&
        create_user_directories #{user_name} &&
        furnish_box #{user_name}
        """
  # insecure - sanitise user_name
  exec cmd, callback
