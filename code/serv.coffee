#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

fs      = require 'fs'

express = require 'express'
request = require 'request'
exec    = require('child_process').exec
mongoose = require 'mongoose'

User = require 'models/user'
Box = require 'models/box'
SSHKey = require 'models/ssh_key'

app = express.createServer()

app.use express.bodyParser()

mongoose.connect process.env['COBALT_DB']

app.get "/", (req, res) ->
  res.send "Hello World"

# Check API key for all POSTs 
# TODO: should this be middleware?
app.post /.*/, (req, res, next) ->
  if req.body.apikey?
    url = "https://scraperwiki.com/froth/check_key/#{req.body.apikey}"
    request.get url, (err, resp, body) ->
      if resp.statusCode is 200
        next()
      else
        res.send {error: "Unauthorised"}, 403
  else
    res.send {error: "No API key supplied"}, 403

# Create a box
app.post "/:box_name$", (req, res) ->
  exports.unix_user_add req.params.box_name, (err, stdout, stderr) ->
    res.send {error: "Error adding user: #{err} #{stderr}"} if err? or stderr?
    new User({apikey: req.body.apikey}).save()
    User.findOne {apikey: req.body.apikey}, (err, user) ->
      return res.send {error: "User not found" }, 404 unless user?
      new Box({user: user._id, name: req.params.box_name}).save()
      res.send 'ok'

# Add an SSH key to a box
app.post "/:box_name/sshkeys$", (req, res) ->
  res.send { error: "SSH Key not specified" }, 400 unless req.body.sshkey?

  Box.findOne {name: req.params.box_name}, (err, box) ->
    return res.send { error: "Box not found" }, 404 unless box?
    key = new SSHKey
      box: box._id
      name: SSHKey.extract_name req.body.sshkey
      key: req.body.sshkey

    key.save ->
      SSHKey.find {box: box._id}, (err, sshkeys) ->
        keys_path = "/opt/cobalt/etc/sshkeys/#{box.name}/authorized_keys"

        keys = for key in sshkeys
          "#{key.key}"

        fs.writeFileSync keys_path, keys.join '\n', 'utf8'
        res.send 'ok'

app.listen 3000

exports.unix_user_add = (box_name, callback) ->
  cmd = """
        cd /root/deployment-hooks && . lib/chroot_user &&
        create_user #{box_name} &&
        create_user_directories #{box_name}
        """

  exec cmd, (err, stdout, stderr) ->
    callback err, stdout, stderr
