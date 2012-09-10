#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

fs      = require 'fs'
child_process = require 'child_process'
os      = require 'os'

express = require 'express'
request = require 'request'
exec    = require('child_process').exec
mongoose = require 'mongoose'

User = require 'models/user'
Box = require 'models/box'
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
app.all "*", (req, res, next) ->
  server_hostname = req.header('host')
  root_url = "http://#{server_hostname}"
  root_url = root_url + ":#{process.env.COBALT_PORT}" unless process.env.COBALT_PORT == '8000'
  next()

# Templating language
app.set('view engine', 'ejs')

# TODO: should this be middleware?
# Check if scraperwiki currently recognises the api key
# If fails, check if that apikey has been valid in the past for box creation
check_api_key = (req, res, next) ->
  res.header('Content-Type', 'application/json')
  apikey = req.body.apikey or req.query.apikey
  if apikey?
    url = "https://scraperwiki.com/froth/check_key/#{apikey}"
    request.get url, (err, resp, body) ->
      body = JSON.parse body
      if resp.statusCode is 200 and req.params.org is body.org
        return next()
      else
        return res.send {error: "Unauthorised"}, 403
  else
    return res.send {error: "No API key supplied"}, 403


# GET REQUESTS
# These should all be idempotent, i.e. make no changes to the server.

app.get "/", (req, res) ->
  res.header('Content-Type', 'application/json')
  res.render('index', {rooturl: root_url})

# Documentation for SSHing to a box.
app.get "/:org/:project/?", (req, res) ->
  box_name = req.params.org + '/' + req.params.project
  res.header('Content-Type', 'application/json')
  Box.findOne {name: box_name}, (err, box) ->
    return res.send { error: "Box not found" }, 404 unless box?
    res.render 'box',
      box_name: box_name
      rooturl: root_url
      server_hostname: server_hostname

# Get file
app.get "/:org/:project/files/*", check_api_key
app.get "/:org/:project/files/*", (req, res) ->
  res.header('Content-Type', 'application/json')
  box_name = req.params.org + '/' + req.params.project
  path = req.path.replace "/#{box_name}/files", ''
  child_process.exec "su -c \"cat /home#{path}\" #{box_name}",
    'utf8',
    (err, stdout, stderr) ->
      if !err and !stderr
        res.send stdout
      else
        res.send {error:"#{path} is not a file"}, 400


# POST REQUESTS
# These should make changes somewhere, likely to the mongodb database

# Check API key for all org/project URLs
app.post "/:org*", check_api_key

# Create a box
app.post "/:org/:project/?", (req, res) ->
  res.header('Content-Type', 'application/json')
  box_name = req.params.org + '/' + req.params.project
  re = /^[a-zA-Z0-9_+-]+\/[a-zA-Z0-9_+-]+$/
  if not re.test box_name
    return res.send {error:
      "Box name should match the regular expression #{String(re)}"}, 404
  new User({apikey: req.body.apikey}).save()
  User.findOne {apikey: req.body.apikey}, (err, user) ->
    return res.send {error: "User not found" }, 404 unless user?
    Box.findOne {name: box_name}, (err, box) ->
      if box
        return res.send {error: "Box already exists"}
      else
        new Box({user: user._id, name: box_name}).save (err) ->
          if err
            console.log "Creating box: #{err} "
            return res.send {error: "Unknown error"}
          else
            exports.unix_user_add box_name, (err, stdout, stderr) ->
              any_stderr = stderr is not ''
              console.log "Error adding user: #{err} #{stderr}" if err? or any_stderr
              return res.send {error: "Unable to create box"} if err? or any_stderr
              return res.send {status: "ok"}

# Add an SSH key to a box
app.post "/:org/:project/sshkeys/?", (req, res) ->
  box_name = req.params.org + '/' + req.params.project

  res.header('Content-Type', 'application/json')
  unless req.body.sshkey? then return res.send { error: "SSH Key not specified" }, 400

  Box.findOne {name: box_name}, (err, box) ->
    return res.send { error: "Box not found" }, 404 unless box?
    User.findOne {apikey: req.body.apikey}, (err, user) ->
      return res.send { error: "Unauthorised" }, 403 unless user?
      return res.send { error: "Unauthorised" }, 403 unless user._id.toString() == box.user.toString()
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
          keys_path = "/opt/cobalt/etc/sshkeys/#{box.name}/authorized_keys"

          keys = for key in sshkeys
            "#{key.key}"

          fs.writeFileSync keys_path, keys.join '\n', 'utf8'
          # Note: octal.  This is deliberate.
          fs.chmodSync keys_path, 0o600
          child_process.exec "chown #{box.name}: #{keys_path}" # insecure
          return res.send {"status": "ok"}

app.listen process.env.COBALT_PORT

exports.unix_user_add = (box_name, callback) ->
  cmd = """
        cd /opt/cobalt &&
        . ./code/box_lib.sh &&
        create_user #{box_name} &&
        create_user_directories #{box_name} &&
        furnish_box #{box_name}
        """
  # insecure - sanitise box_name
  exec cmd, callback
