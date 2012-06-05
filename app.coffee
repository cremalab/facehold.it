express     = require 'express'
path        = require 'path'
fs          = require 'fs'
util        = require 'util'
stylus      = require 'stylus'
http        = require 'http'
request     = require 'request'
redis       = require 'redis'
knox        = require 'knox'
app         = express.createServer()
port        = process.env.PORT || 3001

app.use require('connect-assets')(src : 'public')

app.configure ->
    #app.use express.logger format: ':method :url :status'
    app.use express.static path.join __dirname, 'public'
    app.use stylus.middleware
        debug: true
        force: true
        src: "#{__dirname}/public"
        dest: "#{__dirname}/public"
    app.set 'views', path.join __dirname, 'public/views'
    app.set 'view engine', 'jade'

redis_client    = redis.createClient()
knox_client     = knox.createClient
    key         : process.env.S3_KEY
    secret      : process.env.S3_SECRET
    bucket      : 'faceholdit'


build_fb_photo  = ->
    rando       = Math.floor(Math.random() * 1000000000) + 1
    fb_req      = "https://graph.facebook.com/#{rando}/picture?type=large"

    request.get fb_req, (err, body, response) ->

        image_path = body.socket.pair.cleartext._httpMessage.path

        if image_path != '/static-ak/rsrc.php/v2/yL/r/HsTZSDw4avx.gif'

            piped   = request("https://fbcdn-profile-a.akamaihd.net/#{image_path}").pipe(fs.createWriteStream("#{__dirname}/public/fb_images/#{rando}.jpg"))
            piped.on 'close', ->
                random = "#{rando}.jpg"

                knox_client.putFile piped.path, random, (err, res) ->
                    if err == null
                        redis_client.lpush 'friends', random, (redis_err, redis_res) ->
                            if redis_err then console.log redis_err


get_photo_url = (friends_length, index, next) ->
    rando   = Math.floor(Math.random() * friends_length)
    redis_client.lindex 'friends', rando, (err, res) ->
        s3_url = 'https://s3.amazonaws.com/faceholdit/' + res
        next(s3_url, index)


app.get '/', (req, res, next) ->
    res.end()

app.get '/:number', (req, res, next) ->

    if req.params.number > 100 then res.render 'max'
    else
        photo_urls  = []
        i           = 0

        redis_client.llen 'friends', (err, redis_res) ->
            friends_length = redis_res

            while i < req.params.number
                get_photo_url friends_length, i, (url, index) ->
                    photo_urls.push url

                    if index == parseInt(req.params.number - 1)
                        res.render 'photos', photos : photo_urls
                i++


setInterval (-> build_fb_photo() ), 1000

app.listen port
console.log 'server running on port ' + port 