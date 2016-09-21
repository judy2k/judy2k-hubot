# Description
#   Generate chat messages using markov chains.
#
# Dependencies:
#   cheerio
#   request
#   twitter
#   util
#
# Configuration:
#   None
#
# Commands:
#   hubot markov - post a markov message based on the past N chat messages
#   hubot markov <user> - post a markov message based on chat messages made by <user>
#   hubot markov <url> - post a markov message based on contents of the provided web page (very basic)
#   hubot markov reset - reset the message messageCache
#   hubot twarkov <twitter handle> - post a markov message based on the twerson's last 200 tweets (excluding @replies)
#
# Notes:
#   None
#
# Author:
#   sunpig


twitter = require 'twitter'
util = require 'util'
request = require 'request'
cheerio = require 'cheerio'

twitterOptions = {
  consumer_key: process.env['TWITTER_CONSUMER_KEY']
  consumer_secret: process.env['TWITTER_CONSUMER_SECRET']
  access_token_key: process.env['TWITTER_ACCESS_TOKEN_KEY']
  access_token_secret: process.env['TWITTER_ACCESS_TOKEN_SECRET']
}

IGNORE_USERS = ['hubot', 'github commit bot', 'jenkins'] # lowercase
MAX_MESSAGE_CACHE_LENGTH = 2500 # too small = such boring, too big = very memory
MAX_GENERATED_MESSAGE_LENGTH = 200 # die soon in case of infinite looping case
ASK_HUBOT_REGEX = /hu(gh)?bot\?$/i

twit = new twitter twitterOptions


generateMessage = (msg, corpus) ->
  if corpus.length == 0
    return 'There are no messages for building a chain.'
  else
    transitions = generateTransitions(corpus)

    startWords = (word for own word, data of transitions when data.begins == true)
    word = msg.random(startWords)
    generatedMessage = [word]

    next = msg.random(transitions[word].list)

    i = 0
    while (i++ < MAX_GENERATED_MESSAGE_LENGTH)
      generatedMessage.push(next.word)
      if next.ends
        return generatedMessage.join(' ')
      else
        next = msg.random(transitions[next.word].list)


generateTransitions = (corpus) ->
  saidSplitter = /\s/
  transitions = {}

  for said in corpus
    words = said.split(saidSplitter)

    for i in [0..(words.length - 1)]
      word = words[i]

      transition = transitions[word]
      if not transition
        transition = {
          begins: (i == 0),
          list: []
        }

      transition.list.push({
        word: words[i + 1],
        ends: (i == words.length - 1)
      })

      transitions[word] = transition

  return transitions


sendGenericMarkov = (robot, msg) ->
  messageCache = robot.brain.data.markov.messageCache
  corpus = (message.said for message in messageCache)
  msg.send generateMessage(msg, corpus)


sendMarkovForUrl = (url, msg) ->
  request url, (err, res, body) ->
    $ = cheerio.load body,
      normalizeWhitespace: true
      xmlMode: false
    corpus = []
    $('script').remove()
    $('p').each (index, el) ->
      corpus.push $(this).text()
    try
      msg.send generateMessage(msg, corpus)
    catch e
      msg.send "There was an error generating a Markov chain"


module.exports = (robot) ->

  robot.brain.on 'loaded', =>
    robot.brain.data.markov ||= {}
    robot.brain.data.markov.messageCache ||= []

  robot.respond /markov\s*?$/i, (msg) ->
    sendGenericMarkov(robot, msg)

  # Respond to questions like "what do you think, hubot?"
  robot.hear ASK_HUBOT_REGEX, (msg) ->
    sendGenericMarkov(robot, msg)

  robot.respond /markov (?:(?!reset))(.*)$/i, (msg) ->
    if msg.match[1] and msg.match[1].match /https?:\/\/\S+/
      url = msg.match[1]
      sendMarkovForUrl(url, msg)
    else
      lcUserName = msg.match[1].trim().toLowerCase()
      messageCache = robot.brain.data.markov.messageCache
      corpus = (message.said for message in messageCache when message.user == lcUserName)
      msg.send generateMessage(msg, corpus)

  robot.respond /markov reset/i, (msg) ->
    robot.brain.data.markov.messageCache = []
    msg.send "The Markov cache has been reset."

  robot.respond /twarkov (.*)$/i, (msg) ->
    getOptions = {
      screen_name: msg.match[1].trim().toLowerCase()
      count: 200
      exclude_replies: true
      include_rts: false
    }
    url = '/statuses/user_timeline'
    twit.get url, getOptions, (err, data) ->
      console.error err if err
      if data and data.length
        status_texts = data.map (status) -> status.text
        msg.send generateMessage(msg, status_texts)

  robot.hear /(.*)/i, (msg) ->
    # Ignore messages from specific users
    userName = msg.message.user.real_username || msg.message.user.name
    lcUserName = userName.toLowerCase()
    return if (lcUserName in IGNORE_USERS)

    # Ignore messages containing links
    said = msg.match[1]
    return if said.match(/https?:\/\//gi)

    # Ignore empty or one-word messages
    said = msg.match[1]
    return if said.split(/\s/).length < 2

    # Ignore hubot instructions
    return if said.match(/^hubot/i)

    # Ignore questions posed to hubot directly
    return if said.match(ASK_HUBOT_REGEX)

    # Store message in cache
    messageCache = robot.brain.data.markov.messageCache
    messageCache.push({user: lcUserName, said: said})

    # Limit size of messageCache
    messageCacheLength = messageCache.length
    if messageCacheLength > MAX_MESSAGE_CACHE_LENGTH
      messageCache.splice(0, messageCacheLength - MAX_MESSAGE_CACHE_LENGTH)
