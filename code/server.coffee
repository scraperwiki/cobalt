#!/usr/bin/env coffee

# serv.coffee
# http server for cobalt.

{exec}  = require 'child_process'
fs      = require 'fs'
path    = require 'path'
child_process = require 'child_process'
os      = require 'os'

bcrypt = require 'bcrypt'
express = require 'express'
mongoose = require 'mongoose'
request = require 'request'
checkIdent = require 'ident-express'
_ = require 'underscore'
redis = require 'redis'

liverpool_office_ip = '151.237.236.138'

# The test rely on the redis client being created now at module import time,and rely on the
# listen happening later, when the .start() method is called.
exports.redisClient = redisClient = redis.createClient 6379, process.env.REDIS_SERVER
if /production|staging/.test process.env.NODE_ENV
  redisClient.auth process.env.REDIS_PASSWORD, (err) ->
    if err?
      console.warn 'Redis auth error: ', err

redisClient.on 'pmessage', (pattern, channel, message) ->
  updatePath = "tool/hooks/update"
  #TODO: try catch
  message = JSON.parse message
  origin = message.origin

  url = "https://#{origin.boxServer}/#{origin.box}/#{origin.boxJSON.publish_token}"

  #TODO(pwaller): use async exists
  for box in message.boxes
    if fs.existsSync "/#{process.env.CO_STORAGE_DIR}/home/#{box}/#{updatePath}"
      console.log "Executing update hook for #{box}"
      arg0 = "/home/#{updatePath}"
      cmd = arg0 + ' "$@"'
      run = "su #{box} -l -c '#{cmd}' -- #{arg0} #{url}"
      console.log "Running: ", run
      child_process.exec run

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

mongoose.connect process.env.CU_DB,
  server:
    auto_reconnect: true
    socketOptions:
      keepAlive: 1

port = process.env.COBALT_PORT

# Templating language
app.set('view engine', 'ejs')

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
  if process.env.CO_AVOID_BOX_CHECK == 'yes'
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

# Read optional list of allowed IPs from file.
allowedIP = []
if fs.existsSync("/etc/cobalt/allowed-ip")
  allowedIP = fs.readFileSync("/etc/cobalt/allowed-ip")
  allowedIP = allowedIP.toString().replace /\n$/, ''
  allowedIP = allowedIP.split "\n"
allowedIP = allowedIP.concat [
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
    "176.58.127.147"
    "23.23.37.109"
    liverpool_office_ip
    ]
# Middleware that checks the IP address of the connecting
# partner (which we expect to be custard).
checkIP = (req, res, next) ->
  # Relies on app.set "trust proxy", true in order to get
  # sensible results.
  # :todo: get these from file or environment variable.
  if req.ip in allowedIP
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
  res.send "See https://scraperwiki.com/help/developer/", 200

app.get "/", docs
app.get "/:boxname/?", docs

# POST REQUESTS
# These should make changes somewhere, likely to the mongodb database

console.tick = (stuff...) ->
  # Prints out the time as well as stuff.
  console.log.apply console, [(new Date()).toISOString()].concat(stuff)

maxInFlightMiddleware = (max_in_flight) ->
  inFlightByBox = {}
  return (req, res, next) ->
    if inFlightByBox[req.params.boxname] is undefined
      inFlightByBox[req.params.boxname] = 0

    if inFlightByBox[req.params.boxname] >= max_in_flight
      return res.send 429, error:'Request throttled, too many in flight'

    inFlightByBox[req.params.boxname] += 1
    origEnd = res.end
    res.end = ->
      origEnd.apply res, arguments
      inFlightByBox[req.params.boxname] -= 1
      if inFlightByBox[req.params.boxname] == 0
        delete inFlightByBox[req.params.boxname]
    next()

# Exec endpoint - see wiki for note about security
app.post "/:boxname/exec/?", maxInFlightMiddleware(5), check_api_and_box, (req, res) ->
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

myCheckIdent = (req, res, next) ->
  # ScraperWiki office / localhost
  if req.ip in [liverpool_office_ip, "10.0.0.10", "127.0.0.1"]
    req.ident = 'root'
    next()
  else
    checkIdent req, res, next

requireAuth = (req, res, next) ->
  if req.ident in ["root", "custard"]
    next()
  else
    return res.send 403
      error: 'Only Custard running as Root can contact me'


# Create a box.
# Since we're creating a box, it doesn't have to exist, so we
# don't need to call check_box().

app.post "/box/:newboxname/?", check_api_key, checkIP, myCheckIdent, requireAuth, (req, res) ->
  console.tick "got request create box #{req.params.newboxname}"
  res.header('Content-Type', 'application/json')
  boxname = req.params.newboxname
  re = /^[a-zA-Z0-9_+-.]+$/
  if not re.test boxname
    return res.send 404,
      error: "Box name should match the regular expression #{String(re)}"
  if not req.body.uid?
    return res.send 400,
      error: "Specify a UID"

  User.findOne {apikey: req.body.apikey}, (err, user) ->
    console.tick "found user (again) #{boxname}"
    return res.send 404, {error: "User not found" } unless user?
    exports.unix_user_add boxname, req.body.uid, (err, stdout, stderr) ->
      console.tick "added unix user #{boxname}"
      any_stderr = stderr is not ''
      console.log "Error adding user: #{err} #{stderr}" if err? or any_stderr
      return res.send 500, {error: "Unable to create box"} if err? or any_stderr
      return res.send {"status": "ok"}

# Add an SSH key to a box
app.post "/:boxname/sshkeys/?", checkIP, myCheckIdent, requireAuth, (req, res) ->
  boxname = req.params.boxname

  res.header('Content-Type', 'application/json')
  unless req.body.keys? then return res.send { error: "SSH keys not specified" }, 400

  boxname = req.params.boxname
  dir = "/#{process.env.CO_STORAGE_DIR}/sshkeys/#{boxname}"
  keysPath = "#{dir}/authorized_keys"
  fs.exists dir, (exists) ->
    if not exists
      return res.send 404, error: "Box #{boxname} not found"
    keys = JSON.parse req.body.keys
    fs.writeFile keysPath, keys.join('\n'), encoding: 'utf8', (err) ->
      # Note: octal.  This is deliberate.
      fs.chmod keysPath, 0o600, (err) ->
        child_process.exec "chown #{boxname}: #{keysPath}", (err, stdout, stderr) -> # insecure
          return res.send {"status": "ok"} unless err
          console.log "ERROR: #{err}, stderr: #{stderr}"
          return res.send {"error": "Internal creation error"}

# Add a file to a box
app.post "/:boxname/file/?", check_api_and_box, (req, res) ->
  boxname = req.params.boxname
  dir = "#{process.env.CO_STORAGE_DIR}/home/#{boxname}/incoming"
  fs.stat dir, (err, stat) ->
    if not stat?.isDirectory?()
      console.log "no dir #{dir}"
      return res.send 404, { error: "~/incoming is not a directory or doesn't exist" }

    file = req.files.file
    if not file
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

exports.unix_user_add = (user_name, uid, callback) ->
  console.log "Zarino woz ere"
  homeDir = "#{process.env.CO_STORAGE_DIR}/home"
  cmd = """
        cd /opt/cobalt &&
        . ./code/box_lib.sh &&
        create_user #{user_name} #{uid} &&
        create_user_directories #{user_name}
        """
  # insecure - sanitise user_name
  console.log cmd
  exec cmd, callback

if fs.existsSync(port)
  fs.unlinkSync port

PATTERN = "#{process.env.NODE_ENV}.cobalt.dataset.*.update"

# Call .start() and .stop() to start and stop the server.
server = null
psubscribeListener = null
exports.start = (cb) ->
  server = app.listen port, ->
    if fs.existsSync(port)
      fs.chmodSync port, 0o600
      child_process.exec "chown www-data #{port}"
    redisClient.psubscribe PATTERN
    psubscribeListener = ->
      cb null, server
    redisClient.on 'psubscribe', psubscribeListener

exports.stop = (cb) ->
  console.log "Gracefully stopping..."
  redisClient.punsubscribe PATTERN
  redisClient.removeListener 'psubscribe', psubscribeListener
  psubscribeListener = null
  server.close ->
    server = null
    cb()

# Wait for all connections to finish before quitting
process.on 'SIGTERM', ->
  if server
    server.close ->
      console.warn "All connections finished, exiting"
      process.exit()
  else
    console.warn "No server to stop; exiting"
    process.exit()

  setTimeout ->
    console.error "Could not close connections in time, forcefully shutting down"
    process.exit 1
  , 30*1000
