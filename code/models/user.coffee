mongoose = require 'mongoose'
Schema   = mongoose.Schema

userSchema = new Schema
  apikey: {type: String, unique: true}

module.exports = mongoose.model 'User', userSchema