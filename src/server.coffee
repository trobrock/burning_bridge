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

  message: (client, event, msg) ->
    client.send "#{@hostname} #{@events[event]} #{msg}"

  pong: (client) ->
    client.send "#{@hostname} PONG #{@hostname} :#{@hostname}"

  welcome: (client, user) ->
    @message client, "welcome", "#{user.nick()} Welcome #{user.mask()}"
    @message client, "yourHost", "#{user.nick()} Your host"
    @message client, "created", "#{user.nick()} This server was created"
    @message client, "myInfo", "#{user.nick()} myIrcServer 0.0.1"

  motd: (client, user) ->
    @message client, "motdStart", "#{user.nick()} :- Message of the Day -"
    @message client, "motd", "#{user.nick()} myIrcServer 0.0.1"
    @message client, "motdEnd", "#{user.nick()} :End of /MOTD command."

  list: (client, user) ->
    @message client, "listStart", "#{user.nick()} Channel :Users  Name"
    for room in @rooms.rooms
      @message client, "list", "#{user.nick()} #{room.name.snakeCase()} #{room.users.length} :[]"
    @message client, "listEnd", "#{user.nick()} :End of /LIST"

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
            client.send "#{current_user.mask()} MODE #{target} #{command.args[1]} #{current_user.nick()}"
      when "LIST"
        server.list client, current_user
      when "JOIN"
        channel = command.args[0]
        room = null
        for r in server.rooms.rooms
          room = r if r.name.snakeCase() == channel.replace("#", "")

        users = for user in room.users
          user.name.snakeCase()

        room.join ->
          client.send "#{current_user.mask()} JOIN #{channel}"
          if room.topic
            server.message client, "topic", "#{current_user.nick()} #{channel} :#{room.topic}"
          else
            server.message client, "noTopic", "#{current_user.nick()} #{channel} :No topic is set"
          server.message client, "namesReply", "#{current_user.nick()} = #{channel} :#{users.join(" ")}"
          server.message client, "endNames", "#{current_user.nick()} #{channel} :End of /NAMES list."

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
