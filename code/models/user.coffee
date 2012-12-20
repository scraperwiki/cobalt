bcrypt = require 'bcrypt'
mongoose = require 'mongoose'
Schema = mongoose.Schema

userSchema = new Schema
  apikey: {type: String, unique: true}
  shortname: {type: String, unique: true}
  created: {type: Date, default: Date.now}

  # XXX these fields can be removed next
  email: [String]
  password: String # encrypted, see setPassword method
  isstaff: Boolean

hash = (password, callback) ->
  bcrypt.hash password, 10, (err, hash) ->
    callback hash

userSchema.methods.setPassword = (password, callback) ->
  hash password, (hashed) =>
    @password = hashed
    @save callback

userSchema.methods.objectify = ->
  result = @toObject()
  delete result._id
  delete result.password
  return result

module.exports = mongoose.model 'User', userSchema
