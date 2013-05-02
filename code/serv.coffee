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
checkIdent = require 'ident-express'

Box = require 'models/box'
User = require 'models/user'

app = express()

# Trust the headers from nginx and change req.ip to the real IP
# of the connecting dude.
app.set "trust proxy", true

app.use express.bodyParser()

app.configure 'staging', ->
  app.use express.logger()
  app.use express.errorHandler { dumpExceptions: true, showStack: true}

app.configure 'production', ->
  app.use express.logger()
  app.use express.errorHandler()

mongoose.connect process.env['CU_DB']

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
  fs.readFile "/home/#{user_name}/box.json", 'utf-8', (err, data) ->
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
    next()

check_box = (req, res, next) ->
  if process.env.CO_AVOID_BOX_CHECK
    return next()
  if req.params.boxname?
    Box.findOne {name:req.params.boxname}, (err, box) ->
      if not box?
        return res.send 404, {error: "Box not found"}
      req.box = box
      if req?.user?.shortName not in box.users
        return res.send 403, {error: "Unauthorised for this box"}
      return next()
  else
    return next()

check_api_and_box = [check_api_key, check_box]

# Middleware that checks the IP address of the connecting
# partner (which we expect to be custard).
checkIP = (req, res, next) ->
  # Relies on app.set "trust proxy", true in order to get
  # sensible results.
  # :todo: get these from file or environment variable.
  allowed = [
    "127.0.0.1"
    "178.79.181.194"
    "192.168.129.215"
    "178.79.179.106"
    "192.168.194.236"
    "176.58.122.74"
    "192.168.176.192"
    "178.79.177.136"
    "192.168.186.120"
    "88.211.55.91"
    ]
  if req.ip in allowed
    return next()
  res.send 403, {error: "IP #{req.ip} not allowed"}

rand32 = ->
  # 32 bits of lovely randomness.
  # It so happens that Math.random() only generates 32 random
  # bits on V8 (on node.js and Chrome).
  Math.floor(Math.random() * Math.pow(2, 32))

fresh_apikey = ->
  [rand32(), rand32()].join('-')

# GET REQUESTS
# These should all be idempotent, i.e. make no changes to the server.

docs = (req, res) ->
  res.header('Content-Type', 'application/json')
  res.send "See https://beta.scraperwiki.com/help/developer/", 200

app.get "/", docs
app.get "/:boxname/?", docs

# POST REQUESTS
# These should make changes somewhere, likely to the mongodb database

console.tick = (stuff...) ->
  # Prints out the time as well as stuff.
  console.log.apply console, [(new Date()).toISOString()].concat(stuff)

# Exec endpoint - see wiki for note about security
app.post "/:boxname/exec/?", check_api_and_box, (req, res) ->
  console.tick "got POST exec #{req.params.boxname} #{req.body.cmd}"
  res.removeHeader 'Content-Type'
  cmd = req.body.cmd
  su = child_process.spawn "su", ["-", "-c", "#{cmd}", "#{req.params.boxname}"]
  su.stdout.on 'data', (data) ->
    res.write data
  su.stderr.on 'data', (data) ->
    res.write data
  su.on 'close', (code) ->
    res.end()

  req.on 'end', -> su.kill()
  req.on 'close', -> su.kill()

# Create a box.
# Since we're creating a box, it doesn't have to exist, so we
# don't need to call check_box().
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
    exports.unix_user_add boxname, (err, stdout, stderr) ->
      console.tick "added unix user #{boxname}"
      any_stderr = stderr is not ''
      console.log "Error adding user: #{err} #{stderr}" if err? or any_stderr
      return res.send {error: "Unable to create box"} if err? or any_stderr
      return res.send stdout

myCheckIdent = (req, res, next) ->
  if req.ip is "88.211.55.91"
    req.ident = 'root'
    next()
  else
    checkIdent req, res, next

# Add an SSH key to a box
app.post "/:boxname/sshkeys/?", checkIP, myCheckIdent, (req, res) ->
  if req.ident != 'root'
    return res.send 400,
      error: "Only custard running as root can contact me"
  boxname = req.params.boxname

  res.header('Content-Type', 'application/json')
  unless req.body.keys? then return res.send { error: "SSH keys not specified" }, 400

  boxname = req.params.boxname
  dir = "/opt/cobalt/etc/sshkeys/#{boxname}"
  keysPath = "#{dir}/authorized_keys"
  fs.exists dir, (exists) ->
    if not exists
      return res.send 404, error: "Box #{boxname} not found"
    keys = JSON.parse req.body.keys
    fs.writeFileSync keysPath, keys.join '\n', 'utf8'
    # Note: octal.  This is deliberate.
    fs.chmodSync keysPath, 0o600
    child_process.exec "chown #{boxname}: #{keysPath}", (err, stdout, stderr) -> # insecure
      return res.send {"status": "ok"} unless err
      console.log "ERROR: #{err}, stderr: #{stderr}"
      return res.send {"error": "Internal creation error"}

# Add a file to a box
app.post "/:boxname/file/?", check_api_and_box, (req, res) ->
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
      # TODO: there must be a better way of doing this,
      # perhaps easyXDM with file upload + metadata calls
      # If there's a # in the URL, read the JSON object out
      if next.indexOf('#') > -1
        text = decodeURIComponent(next)
        obj = JSON.parse text.substr(text.indexOf '{')
        obj.filePath = file.name
        json = encodeURIComponent JSON.stringify(obj)
        next = "#{next.split('#')[0]}##{json}"
      else
        next = "#{next}##{dir}/#{file.name}"
      return res.redirect 301, next

if existsSync(port)
  fs.unlinkSync port

app.listen port, ->
  if existsSync(port)
    fs.chmodSync port, 0o600
    child_process.exec "chown www-data #{port}"


exports.unix_user_add = (user_name, callback) ->
  cmd = """
        cd /opt/cobalt &&
        . ./code/box_lib.sh &&
        create_user #{user_name} &&
        create_user_directories #{user_name}
        sh ./code/templates/box.json.template
        """
  # insecure - sanitise user_name
  exec cmd, callback
