mongoose = require 'mongoose'
Schema   = mongoose.Schema
ObjectId = Schema.ObjectId

boxSchema = new Schema
  name: {type: String, unique: true}
  users: [String]

module.exports = mongoose.model 'Box', boxSchema
