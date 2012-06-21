#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

express = require 'express'
request = require 'request'
exec    = require('child_process').exec

app = express.createServer()

app.use express.bodyParser()

# TODO: Refactor routes into separate class
app.get "/", (req, res) ->
  res.send "Hello World"

app.post "/:box_name", (req, res) ->
  res.contentType 'json'
  if req.body.apikey?
    url = "https://scraperwiki.com/froth/check_key/#{req.body.apikey}"
    request.get url, (err, resp, body) ->
      if resp.statusCode is 200
        exports.user_add req.params.box_name, (err, stdout, stderr) ->
          res.send '{ "error": "Error adding user '+err+stderr+'" }' if err? or stderr?
          res.send 'ok'
      else
        res.send '{ "error": "Unauthorised" }', 403
  else
    res.send '{ "error": "No API key supplied" }', 403

app.listen 3000

exports.user_add = (box_name, callback) ->
  cmd = """
        cd /root/deployment-hooks && . lib/chroot_user &&
        create_user #{box_name} &&
        create_user_directories #{box_name}
        """

  exec cmd, (err, stdout, stderr) ->
    callback err, stdout, stderr

