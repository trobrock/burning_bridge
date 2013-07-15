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

class Server
  clients: []
  rooms: new Rooms()
  hostname: "localhost"

  add_client: (client) ->
    @clients.push client

  message: (client, msg) ->
    client.send "#{@hostname} #{msg}"

server = new Server()

handler = (socket) ->
  current_user = null

  client = new Client(socket)
  server.add_client client

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
        server.message client, "001 #{current_user.nick()} Welcome #{current_user.mask()}"
        server.message client, "002 #{current_user.nick()} Your host"
        server.message client, "003 #{current_user.nick()} This server was created"
        server.message client, "004 #{current_user.nick()} myIrcServer 0.0.1"

        server.message client, "375 #{current_user.nick()} :- Message of the Day -"
        server.message client, "372 #{current_user.nick()} myIrcServer 0.0.1"
        server.message client, "376 #{current_user.nick()} :End of /MOTD command."
      when "PING"
        server.message client, "PONG localhost :localhost"
      when "MODE"
        target = command.args[0]
        if target.match /^\#/
          if command.args[1]
            client.send "#{current_user.mask()} MODE #{target} #{command.args[1]} #{current_user.nick()}"
      when "LIST"
        server.message client, "321 #{current_user.nick()} Channel :Users  Name"
        for room in server.rooms.rooms
          server.message client, "322 #{current_user.nick()} #{room.name.snakeCase()} #{room.users.length} :[]"
        server.message client, "323 #{current_user.nick()} :End of /LIST"
      when "JOIN"
        channel = command.args[0]
        room = null
        for r in server.rooms.rooms
          room = r if r.name.snakeCase() == channel.replace("#", "")

        users = for user in room.users
          user.name.snakeCase()

        room.join ->
          client.send "#{current_user.mask()} JOIN #{channel}"
          server.message client, "331 #{current_user.nick()} #{channel} :No topic is set"
          server.message client, "353 #{current_user.nick()} = #{channel} :#{users.join(" ")}"
          server.message client, "366 #{current_user.nick()} #{channel} :End of /NAMES list."

          # TODO: Move this to the Rooms object to have one listener per room per server
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
    server.clients.splice(server.clients.indexOf(client), 1)
    console.log "Client disconnected"

  socket.on "error", (e) ->
    console.log "Caught fatal error:", e

net.createServer(handler).listen 6666, ->
  console.log "Started listening on 6666"
