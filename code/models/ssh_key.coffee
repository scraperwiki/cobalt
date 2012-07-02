mongoose = require 'mongoose'
Schema   = mongoose.Schema
ObjectId = Schema.ObjectId

sshKeySchema = new Schema
  box: ObjectId
  name: {type: String}
  key: {type: String}

sshKeySchema.statics.extract_name = (key) ->
  return false if (!key? or key.length < 1)
  (key.trim().match /(?:ssh-rsa|ssh-dss)\s+[^\s]+\s*(.*)$/m)[1]

module.exports = mongoose.model 'SSHKey', sshKeySchema
