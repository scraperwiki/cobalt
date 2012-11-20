mongoose = require 'mongoose'
Schema   = mongoose.Schema

userSchema = new Schema
  apikey: {type: String, unique: true}
  shortname: {type: String, unique: true}
  email: [String]
  displayname: String
  password: String
  isstaff: Boolean

module.exports = mongoose.model 'User', userSchema
