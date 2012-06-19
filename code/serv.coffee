#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

express = require 'express'
request = require 'request'
exec    = require('child_process').exec

app = express.createServer()

app.use express.bodyParser()

app.get "/", (req, res) ->
  res.send "Hello World"

app.post "/:box_name", (req, res) ->
  res.contentType 'json'
  if req.body.apikey?
    url = "https://scraperwiki.com/froth/check_key/#{req.body.apikey}"
    request.get url, (err, resp, body) ->
      if resp.statusCode is 200
        #exec 'ls', (err, stdout, stderr) ->
        res.send 'ok'
      else
        res.send '{ "error": "Unauthorised" }', 403
  else
    res.send '{ "error": "No API key supplied" }', 403

app.listen 3000

exports.user_add = ->

