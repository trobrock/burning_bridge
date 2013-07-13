class Command
  command: null
  args: []

  constructor: (@command, @args) ->

Command.parse = (data) ->
  parts = data.trim().split new RegExp("/ :/")
  args = parts[0].split(' ')

  parts = [parts.shift(), parts.join(' :')]

  if parts.length > 0
    args.push(parts[1])

  if (data.match(/^:/))
    args[1] = args.splice(0, 1, args[1])
    args[1] = (args[1] + '').replace(/^:/, '')

  new Command(args[0].toUpperCase(), args.slice(1))

exports.Command = Command
