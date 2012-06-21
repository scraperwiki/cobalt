mongoose = require 'mongoose'
Schema   = mongoose.Schema
ObjectId = Schema.ObjectId

boxSchema = new Schema
  user: ObjectId
  name: {type: String, unique: true}

module.exports = mongoose.model 'Box', boxSchema