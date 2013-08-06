DatabaseCleaner = require "database-cleaner"
databaseCleaner = new DatabaseCleaner "mongodb"
connect = require("mongodb").connect
DB = "mongodb://localhost/cu-test"
connect DB, (err, db) ->
  databaseCleaner.clean db, ->
    console.log "#{DB} cleaned"
    db.close()
