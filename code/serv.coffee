#!/usr/bin/env coffee

# serv.coffee
# http server for cobalt.

{exec}  = require 'child_process'
fs      = require 'fs'
path    = require 'path'
# Avoids warning.  Remove when we definitely use a node version with
# the "modern" fs.existsSync.
existsSync = fs.existsSync || path.existsSync
child_process = require 'child_process'
os      = require 'os'

bcrypt = require 'bcrypt'
express = require 'express'
mongoose = require 'mongoose'
request = require 'request'

Box = require 'models/box'
SSHKey = require 'models/ssh_key'
User = require 'models/user'

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
check_auth = (apikey, callback) ->
  User.findOne {apikey: apikey}, (err, user) ->
    if user
      callback true, user
    else
      callback false, null

# Middleware that checks apikey and issues HTTP status as appropriate.
# If authorised, req.user is set.
# If a "boxname" parameter is part of the route, then the apikey is checked
# against the box (specifically, that the user of the apikey is the user that
# originally created the box), req.box is set.
check_api_key = (req, res, next) ->
  res.header('Content-Type', 'application/json')
  apikey = req.body.apikey or req.query.apikey
  if not apikey?
    return res.send 403, {error: "No API key supplied"}
  check_auth apikey, (authorised, user) ->
    if not authorised
      return res.send 403, {error: "Unauthorised"}
    req.user = user
    if req.params.boxname?
      Box.findOne {name:req.params.boxname}, (err, box) ->
        if not box?
          return res.send 404, {error: "Box not found"}
        req.box = box
        if user._id.toString() != box.user.toString()
          return res.send 403, {error: "Unauthorised for this box"}
        return next()
    else
      return next()

rand32 = ->
  # 32 bits of lovely randomness.
  # It so happens that Math.random() only generates 32 random
  # bits on V8 (on node.js and Chrome).
  Math.floor(Math.random() * Math.pow(2, 32))

fresh_apikey = ->
  [rand32(), rand32()].join('-')

# GET REQUESTS
# These should all be idempotent, i.e. make no changes to the server.

app.get "/", (req, res) ->
  res.header('Content-Type', 'application/json')
  res.render('index', {rooturl: root_url})

app.get "/ierghjoig/:profile/?", check_api_key, (req, res) ->
  User.findOne {shortname: req.params.profile}, (err, profile) ->
    res.json profile.objectify()


# Documentation for SSHing to a box.
app.get "/:boxname/?", (req, res) ->
  boxname = req.params.boxname
  res.header('Content-Type', 'application/json')
  check_auth req.query.apikey, (authorised) ->
    Box.findOne {name: boxname}, (err, box) ->
      return res.send { error: "Box not found" }, 404 unless box?
      box_settings boxname, (err, settings) ->
        res.render 'box',
          apikey: if authorised then req.query.apikey else '<apikey>'
          box_name: boxname
          rooturl: root_url
          server_hostname: server_hostname
          publish_token: if authorised and settings.publish_token then settings.publish_token else undefined


# POST REQUESTS
# These should make changes somewhere, likely to the mongodb database

console.tick = (stuff...) ->
  # Prints out the time as well as stuff.
  console.log.apply console, [(new Date()).toISOString()].concat(stuff)

# Exec endpoint - see wiki for note about security
app.post "/:boxname/exec/?", check_api_key, (req, res) ->
  console.tick "got POST exec #{req.params.boxname} #{req.body.cmd}"
  res.removeHeader 'Content-Type'
  cmd = req.body.cmd
  su = child_process.spawn "su", ["-c", "#{cmd}", "#{req.params.boxname}"]
  su.stdout.on 'data', (data) ->
    res.write data
  su.stderr.on 'data', (data) ->
    res.write data
  su.on 'exit', (code) ->
    res.end()

  req.on 'end', -> su.kill()
  req.on 'close', -> su.kill()

# Create a new profile - staff only
# Don't want to check_api_key because this includes its own staff check
app.post "/:profile/?", (req, res) ->
  console.tick "got request create profile #{req.params.profile}"
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
        apikey: req.body.newApikey or fresh_apikey()
      ).save (err) ->
        console.log err
        User.findOne {shortname: req.params.profile}, (err, user) ->
          userobj = user.objectify()
          # 201 Created, RFC2616
          return res.json userobj, 201

# Create a box.
# Calling the parameter "newboxname" avoids the check in check_api_key that the
# box has to exist.  Since we're creating a box, it doesn't have to exist.
app.post "/box/:newboxname/?", check_api_key, (req, res) ->
  console.tick "got request create box #{req.params.newboxname}"
  res.header('Content-Type', 'application/json')
  boxname = req.params.newboxname
  re = /^[a-zA-Z0-9_+-.]+$/
  if not re.test boxname
    return res.send 404,
      error: "Box name should match the regular expression #{String(re)}"
  User.findOne {apikey: req.body.apikey}, (err, user) ->
    console.tick "found user (again) #{boxname}"
    return res.send 404, {error: "User not found" } unless user?
    Box.findOne {name: boxname}, (err, box) ->
      console.tick "checked box existence #{boxname}"
      if box
        return res.send {error: "Box already exists"}
      new Box({user: user._id, name: boxname}).save (err) ->
        console.tick "created database entity: box #{boxname}"
        if err
          console.log "Creating box: #{err} "
          return res.send 404, {error: "Unknown error"}
        exports.unix_user_add boxname, (err, stdout, stderr) ->
          console.tick "added unix user #{boxname}"
          any_stderr = stderr is not ''
          console.log "Error adding user: #{err} #{stderr}" if err? or any_stderr
          return res.send {error: "Unable to create box"} if err? or any_stderr
          return res.send {status: "ok"}

# Add an SSH key to a box
app.post "/:boxname/sshkeys/?", check_api_key, (req, res) ->
  boxname = req.params.boxname

  res.header('Content-Type', 'application/json')
  unless req.body.sshkey? then return res.send { error: "SSH Key not specified" }, 400

  box = req.box
  if not box?
    # Mysterious because check_api_key should have already checked the box
    return res.send 404, { error: "Mysteriously, box not found" }
  try
    name = SSHKey.extract_name req.body.sshkey
  catch TypeError
    return res.send 400, { error: "SSH Key format not valid" }
  unless name then return res.send 400, { error: "SSH Key has no name" }
  key = new SSHKey
    box: box._id
    name: name
    key: req.body.sshkey

  key.save ->
    SSHKey.find {box: box._id}, (err, sshkeys) ->
      keys_path = "/opt/cobalt/etc/sshkeys/#{boxname}/authorized_keys"

      keys = for key in sshkeys
        "#{key.key}"

      fs.writeFileSync keys_path, keys.join '\n', 'utf8'
      # Note: octal.  This is deliberate.
      fs.chmodSync keys_path, 0o600
      child_process.exec "chown #{boxname}: #{keys_path}", (err, stdout, stderr) -> # insecure
        return res.send {"status": "ok"} unless err
        console.log "ERROR: #{err}, stderr: #{stderr}"
        return res.send {"error": "Internal creation error"}

# Add a file to a box
app.post "/:boxname/file/?", check_api_key, (req, res) ->
  boxname = req.params.boxname
  dir = "/home/#{boxname}/incoming"
  existsSync = fs.existsSync || path.existsSync
  if ! existsSync dir
    console.log "no #{dir}"
    return res.send 404, { error: "no ~/incoming directory" }
  if ! fs.statSync(dir).isDirectory()
    console.log "not dir #{dir}"
    return res.send 404, { error: "~/incoming is not a directory" }
  file = req.files.file
  if ! file
    return res.send 400, { error: "no file" }
  
  # Remove all characters apart from a few select safe ones.
  file.name = file.name.replace /[^.a-zA-Z0-9_+-]/g, ''
  child_process.exec "mv #{file.path} #{dir}/#{file.name}", ->
    child_process.exec "chown #{boxname}: #{dir}/#{file.name}", ->
      next = req.body.next || "/"
      next = "#{next}##{dir}/#{file.name}"
      return res.redirect 301, next

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
