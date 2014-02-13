Campfire     = require("campfire").Campfire
EventEmitter = require("events").EventEmitter

class User
  id: -1
  real_name: null
  username: null
  hostname: null

  constructor: (subdomain, api_token, @irc_client, @id = -1) ->
    @events = new EventEmitter()
    @campfire = new Campfire(
      ssl: true,
      token: api_token,
      account: subdomain
    )

    @_fetch()

  mask: ->
    "#{@nick()}!#{@username}@#{@campfire.domain}"

  speak_in_room: (channel, message) ->
    @find_room channel, (room) =>
      room.speak @_clean_message(room, message)

  leave_room: (channel, message) ->
    @find_room channel, (room) =>
      room.leave =>
        @irc_client.send "#{@mask()} PART #{channel} :#{message}"

  find_room: (channel, callback) ->
    @campfire.presence (err, rooms) =>
      for room in rooms
        if room.name.snakeCase() == channel.replace("#", "")
          @campfire.room room.id, (err, r) ->
            callback(r)

  on: ->
    @events.on.apply @events, arguments

  once: ->
    @events.once.apply @events, arguments

  nick: (new_nick) ->
    return @_nick unless new_nick?

    @irc_client.send "#{@mask()} NICK :#{new_nick}" if @_nick
    @_nick = new_nick

  _clean_message: (room, message, callback) ->
    tokens = message.split(" ").map (token) ->
      possible_name = token.match /(^| )([a-z]+_[a-z]+)([^ ]*)/
      if possible_name
        name = possible_name[0].replace(/^ /, "")
        for user in room.users
          name = "#{user.name}#{possible_name[3]}" if user.name.snakeCase() == possible_name[2]
        name
      else
        token
    tokens.join(" ")

  _fetch: ->
    @_fetchFunction() (err, data) =>
      user = data.user
      console.log user
      @nick        user.name.snakeCase()
      @username  = @nick()
      @real_name = user.name
      @id        = user.id
      @events.emit "fetched"

  _fetchFunction: ->
    if @id > -1
      @campfire.user.bind(@campfire, @id)
    else
      @campfire.me.bind(@campfire)

exports.User = User
