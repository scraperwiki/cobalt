mongoose = require 'mongoose'
Schema   = mongoose.Schema

tokenSchema = new Schema
  token: {type: String, unique: true}
  shortname: String
  created: {type: Date, default: Date.now}

module.exports = mongoose.model 'Token', tokenSchema
