#!/usr/bin/env coffee

# serv.ps
# http server for cobalt.

express = require 'express'
app = express.createServer()
app.get "/", (req, res) ->
  res.send "Hello World"

app.listen 3000
