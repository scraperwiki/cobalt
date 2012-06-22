mongoose = require 'mongoose'
Schema   = mongoose.Schema
ObjectId = Schema.ObjectId

sshKeySchema = new Schema
  box: ObjectId
  name: {type: String, unique: true}
  key: {type: String, unique: true}

sshKeySchema.statics.extract_name = (key) ->
  (key.trim().match /(?:ssh-rsa|ssh-dss).*\s(.*)$/m)[1]

module.exports = mongoose.model 'SSHKey', sshKeySchema
