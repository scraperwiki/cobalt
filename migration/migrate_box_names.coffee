fs = require 'fs'

request = require 'request'
mongoose = require 'mongoose'
async = require 'async'

User = require 'models/user'
Box = require 'models/box'
SSHKey = require 'models/ssh_key'

mongoose.connect process.env['COBALT_DB']

passwd_file = fs.readFileSync 'passwd_box', 'utf-8'

get_new_name = (row, callback) ->
  box_name = row.split(':')[0]
  Box.findOne {name: box_name}, (err, box) ->
    if box? and box.user?
      User.findOne {_id: box.user}, (err, user) ->
        url = "https://scraperwiki.com/froth/check_key/#{user.apikey}"
        request.get url, (err, resp, body) ->
          body = JSON.parse body
          if resp.statusCode is 200
            new_name =  "#{body.org}/#{box.name}"
            box.name = new_name
            box.save (err) ->
              console.log err if err?
              callback()
    else
      # System users will reach here
      callback()

async.forEach passwd_file.split('\n'), get_new_name, (err) ->
  console.log err if err?
  process.exit 0
