net      = require "net"
carrier  = require "carrier"
fs       = require "fs"
User     = require("./user.js").User
Command  = require("./command.js").Command
Rooms    = require("./rooms.js").Rooms
require('longjohn')

configuration = JSON.parse(fs.readFileSync("./config/config.json").toString())

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
  events: {
    welcome: "001",
    yourHost: "002",
    created: "003",
    myInfo: "004",
    motdStart: "375",
    motd: "372",
    motdEnd: "376",
    listStart: "321",
    list: "322",
    listEnd: "323",
    topic: "332",
    noTopic: "331",
    namesReply: "353",
    endNames: "366"
  }

  add_client: (client) ->
    @clients.push client

  remove_client: (client) ->
    @clients.splice(@clients.indexOf(client), 1)

  broadcast_event: (client, event, msg) ->
    @broadcast client, "#{@events[event]} #{msg}"

  broadcast: (client, msg) ->
    client.send "#{@hostname} #{msg}"

  message: (client, user, msg) ->
    client.send "#{user.mask()} #{msg}"

  pong: (client) ->
    @broadcast client, "PONG #{@hostname} :#{@hostname}"

  welcome: (client, user) ->
    @broadcast_event client, "welcome", "#{user.nick()} Welcome #{user.mask()}"
    @broadcast_event client, "yourHost", "#{user.nick()} Your host"
    @broadcast_event client, "created", "#{user.nick()} This server was created"
    @broadcast_event client, "myInfo", "#{user.nick()} myIrcServer 0.0.1"

  motd: (client, user) ->
    @broadcast_event client, "motdStart", "#{user.nick()} :- Message of the Day -"
    @broadcast_event client, "motd", "#{user.nick()} myIrcServer 0.0.1"
    @broadcast_event client, "motdEnd", "#{user.nick()} :End of /MOTD command."

  list: (client, user) ->
    @broadcast_event client, "listStart", "#{user.nick()} Channel :Users  Name"
    for room in @rooms.rooms
      @broadcast_event client, "list", "#{user.nick()} #{room.name.snakeCase()} #{room.users.length} :[]"
    @broadcast_event client, "listEnd", "#{user.nick()} :End of /LIST"

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
        server.welcome client, current_user
        server.motd    client, current_user
      when "PING"
        server.pong client
      when "MODE"
        target = command.args[0]
        if target.match /^\#/
          if command.args[1]
            server.message client, current_user, "MODE #{target} #{command.args[1]} #{current_user.nick()}"
      when "LIST"
        server.list client, current_user
      when "NAMES"
        channel = command.args[0]
        room = null

        for r in server.rooms.rooms
          room = r if r.name.snakeCase() == channel.replace("#", "")

        users = for user in room.users
          user.name.snakeCase()

        server.broadcast_event client, "namesReply", "#{current_user.nick()} = #{channel} :#{users.join(" ")}"
        server.broadcast_event client, "endNames", "#{current_user.nick()} #{channel} :End of /NAMES list."
      when "JOIN"
        channel = command.args[0]
        room = null
        for r in server.rooms.rooms
          room = r if r.name.snakeCase() == channel.replace("#", "")

        users = for user in room.users
          user.name.snakeCase()

        room.join ->
          server.message client, current_user, "JOIN #{channel}"
          if room.topic
            server.broadcast_event client, "topic", "#{current_user.nick()} #{channel} :#{room.topic}"
          else
            server.broadcast_event client, "noTopic", "#{current_user.nick()} #{channel} :No topic is set"
          server.broadcast_event client, "namesReply", "#{current_user.nick()} = #{channel} :#{users.join(" ")}"
          server.broadcast_event client, "endNames", "#{current_user.nick()} #{channel} :End of /NAMES list."

          # TODO: Move this to the Rooms object to have one listener per room per server
          room.listen (message) =>
            return if message.type != "TextMessage"
            return if message.userId == current_user.id

            user = new User(configuration.subdomain, configuration.token, client, message.userId)
            user.once "fetched", ->
              name = user.real_name.snakeCase()
              server.message client, user, "PRIVMSG #{channel} :#{message.body}"
      when "PRIVMSG"
        channel = command.args[0]
        message = command.args.slice(1).join(" ").substr(1)

        current_user.speak_in_room(channel, message)
      when "PART"
        channel = command.args[0]
        message = command.args[1].substr(1)

        current_user.leave_room(channel, message)

  socket.on "end", ->
    server.remove_client client
    console.log "Client disconnected"

  socket.on "error", (e) ->
    console.log "[socket] Caught fatal error:", e

s = net.createServer(handler)
s.listen 6666, ->
  console.log "Started listening on 6666"

s.on "error", (e) ->
  console.log "[server] Caught fatal error:", e
