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

#redis_client    = redis.createClient()
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
                knox_client.putFile piped.path, "#{rando}.jpg", (err, res) ->
                    #save to s3
                        


get_photo_url = ->
    rando   = Math.floor(Math.random() * redis_client.llen 'photos') + 1
    s3_url  = redis_client.lindex rando
    return s3_url


app.get '/', (req, res, next) ->
    res.end()

app.get '/:number', (req, res, next) ->
    ###
    photo_urls = []
    for x in req.pramas.number
        photo_urls.push get_photo_url()

    res.render 'photos' photos : photo_urls
    ###

setInterval (-> build_fb_photo() ), 1000

app.listen port
console.log 'server running on port ' + port 