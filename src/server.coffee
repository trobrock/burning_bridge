net      = require "net"
carrier  = require "carrier"
fs       = require "fs"
Campfire = require("campfire").Campfire
User     = require("./user.js").User
Command  = require("./command.js").Command
Rooms    = require("./rooms.js").Rooms

configuration = JSON.parse(fs.readFileSync("./config/config.json").toString())
campfire_subdomain = configuration.subdomain
campfire_token     = configuration.token
campfire = new Campfire(
  ssl: true,
  token: campfire_token,
  account: campfire_subdomain
)

String::snakeCase = ->
  @split(" ").map((word) ->
    word.toLowerCase()
  ).join("_")

class Client
  constructor: (@socket) ->
  send: (message) ->
    console.log "[s] :#{message}"
    @socket.write ":#{message}\r\n"

rooms = new Rooms()

handler = (socket) ->
  client = new Client(socket)
  current_user = null

  socket.name = socket.remoteAddress + ":" + socket.remotePort

  carrier.carry socket, (line) ->
    command = Command.parse(line)
    console.log "[r] #{command.command} with args #{command.args}"

    switch command.command
      when "PASS"
        [subdomain, api_token] = command.args[0].split(":")
        current_user = new User(subdomain, api_token, client)
      when "NICK"
        current_user.nick(command.args[0]) unless current_user.nick()
      when "USER"
        current_user.username = command.args[0]
        current_user.hostname = command.args[1]
        client.send "localhost 001 #{current_user.nick()} Welcome #{current_user.mask()}"
        client.send "localhost 002 #{current_user.nick()} Your host"
        client.send "localhost 003 #{current_user.nick()} This server was created"
        client.send "localhost 004 #{current_user.nick()} myIrcServer 0.0.1"

        client.send "localhost 375 #{current_user.nick()} :- Message of the Day -"
        client.send "localhost 372 #{current_user.nick()} myIrcServer 0.0.1"
        client.send "localhost 376 #{current_user.nick()} :End of /MOTD command."
      when "PING"
        client.send "localhost PONG localhost :localhost"
      when "MODE"
        target = command.args[0]
        if target.match /^\#/
          if command.args[1]
            client.send "#{current_user.mask()} MODE #{target} #{command.args[1]} #{current_user.nick()}"
      when "LIST"
        client.send "localhost 321 #{current_user.nick()} Channel :Users  Name"
        for room in rooms.rooms
          client.send "localhost 322 #{current_user.nick()} #{room.name.snakeCase()} #{room.users.length} :[]"
        client.send "localhost 323 #{current_user.nick()} :End of /LIST"
      when "JOIN"
        channel = command.args[0]
        room = null
        for r in rooms.rooms
          room = r if r.name.snakeCase() == channel.replace("#", "")

        users = for user in room.users
          user.name.snakeCase()

        room.join ->
          client.send "#{current_user.mask()} JOIN #{channel}"
          client.send "localhost 331 #{current_user.nick()} #{channel} :No topic is set"
          client.send "localhost 353 #{current_user.nick()} = #{channel} :#{users.join(" ")}"
          client.send "localhost 366 #{current_user.nick()} #{channel} :End of /NAMES list."

          # TODO: How do we disconnect this on PART
          room.listen (message) =>
            return if message.type != "TextMessage"
            return if message.userId == current_user.id

            user = new User(campfire_subdomain, campfire_token, client, message.userId)
            user.once "fetched", ->
              name = user.real_name.snakeCase()
              client.send "#{user.mask()} PRIVMSG #{channel} :#{message.body}"
      when "PRIVMSG"
        channel = command.args[0]
        message = command.args.slice(1).join(" ").substr(1)

        current_user.speak_in_room(channel, message)
      when "PART"
        channel = command.args[0]
        message = command.args[1].substr(1)

        current_user.leave_room(channel, message)

  socket.on "end", ->
    console.log "Client disconnected"

  socket.on "error", (e) ->
    console.log "Caught fatal error:", e

server = net.createServer(handler).listen 6666, ->
  console.log "Started listening on 6666"
