bcrypt = require 'bcrypt'
mongoose = require 'mongoose'
Schema = mongoose.Schema

userSchema = new Schema
  apikey: {type: String, unique: true}
  shortname: {type: String, unique: true}
  email: [String]
  displayname: String
  password: String # encrypted, see setPassword method
  isstaff: Boolean
  created: {type: Date, default: Date.now}

hash = (password, callback) ->
  bcrypt.hash password, 10, (err, hash) ->
    callback hash

userSchema.methods.setPassword = (password, callback) ->
  hash password, (hashed) =>
    @.password = hashed
    @.save callback

module.exports = mongoose.model 'User', userSchema
