mongoose = require 'mongoose'
Schema   = mongoose.Schema
ObjectId = Schema.ObjectId

boxSchema = new Schema
  name: {type: String, unique: true}
  users: [String]
  user: Schema.Types.ObjectId

module.exports = mongoose.model 'Box', boxSchema
