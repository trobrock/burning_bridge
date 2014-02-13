fs           = require "fs"
Campfire     = require("campfire").Campfire
EventEmitter = require("events").EventEmitter

configuration = JSON.parse(fs.readFileSync("./config/config.json").toString())
class Rooms
  campfire: new Campfire(
    ssl: true,
    token: configuration.token,
    account: configuration.subdomain
  )
  rooms: []

  constructor: ->
    @events = new EventEmitter()
    @_sync()

  on: ->
    @events.on.apply @events, arguments

  _sync: ->
    @campfire.rooms (err, all_rooms) =>
      for room in all_rooms
        @campfire.room room.id, (err, r) =>
          @rooms.push r
          channel = "##{r.name.toLowerCase().replace(" ", "_")}"
          r.listen (message) =>
            @events.emit "message:#{channel}", message

exports.Rooms = Rooms
