fs       = require "fs"
Campfire = require("campfire").Campfire

configuration = JSON.parse(fs.readFileSync("./config/config.json").toString())
class Rooms
  campfire: new Campfire(
    ssl: true,
    token: configuration.token,
    account: configuration.subdomain
  )
  rooms: []

  constructor: ->
    @_sync()

  _sync: ->
    @campfire.rooms (err, all_rooms) =>
      for room in all_rooms
        @campfire.room room.id, (err, r) =>
          @rooms.push r

exports.Rooms = Rooms
