#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

express = require 'express'
app = express.createServer()

app.use express.bodyParser()

app.get "/", (req, res) ->
  res.send "Hello World"

app.post "/:box_name", (req, res) ->
  if req.body.apikey?
    res.send "OK"
  else
    res.send "DENIED", 403

app.listen 3000
