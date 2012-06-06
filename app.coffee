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

S3_PATH     = 'https://s3.amazonaws.com/faceholdit/'

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

redis_client    = redis.createClient(2586, '50.30.35.9')
 
redis_client.auth process.env.REDIS_PASS, (err) ->
    setInterval (-> build_fb_photo() ), 1000

knox_client     = knox.createClient
    key         : process.env.S3_KEY
    secret      : process.env.S3_SECRET
    bucket      : 'faceholdit'

z = 0

build_fb_photo  = ->
    rando       = Math.floor(Math.random() * 1000000000) + 1
    fb_req      = "https://graph.facebook.com/#{rando}/picture?type=large"

    request.get fb_req, (err, resp, body) ->

        if resp.socket

            image_path = resp.socket.pair.cleartext._httpMessage.path

            if image_path != '/static-ak/rsrc.php/v2/yL/r/HsTZSDw4avx.gif'
                piped = request("https://fbcdn-profile-a.akamaihd.net/#{image_path}").pipe(fs.createWriteStream("#{__dirname}/public/fb_images/#{rando}.jpg"))
                piped.on 'close', ->
                    random = "#{rando}.jpg"

                    knox_client.putFile piped.path, random, (err, res) ->
                        if err == null
                            fs.unlink "#{__dirname}/public/fb_images/#{rando}.jpg", (delete_err) ->
                                if delete_err then console.log delete_err
                            redis_client.lpush 'friends', random, (redis_err, redis_res) ->
                                if redis_err then console.log redis_err
                                z++
                                console.log z


get_photo_url = (max, index, next) ->
    rando = Math.floor(Math.random() * max)
    redis_client.lindex 'friends', rando, (err, res) ->
        s3_url = S3_PATH + res
        next(s3_url, index)


get_photo_count = (next) ->
    redis_client.llen 'friends', (err, res) ->
        next(res)


app.get '/', (req, res, next) ->
    res.redirect '/picture'
    
app.get '/image', (req, res, next) ->
    res.redirect '/picture'
    
app.get '/picture', (req, res, next) ->
    get_photo_count (photo_count) ->
        get_photo_url photo_count, 0, (url, index) ->
            request url, (err, resp, body) ->
                rando = Math.floor(Math.random() * 1000000)
                piped = request(url).pipe(fs.createWriteStream("#{__dirname}/public/from_s3/#{rando}.jpg"))
                piped.on 'error', (err) ->
                    console.log 'error making image'
                    console.log err
                piped.on 'close', ->
                    setTimeout (->
                        fs.unlink "#{__dirname}/public/from_s3/#{rando}.jpg", (delete_err) ->
                            if delete_err then console.log delete_err
                    ), 500
                    res.sendfile piped.path


app.get '/:number', (req, res, next) ->

    if req.params.number > 100 then res.render 'max'
    else if req.params.number == '1' then res.redirect '/picture'

    else
        photo_urls  = []
        i           = 0

        get_photo_count (photo_count) ->

            while i < req.params.number
                get_photo_url photo_count, i, (url, index) ->
                    photo_urls.push url

                    if index == parseInt(req.params.number - 1)
                        res.render 'photos', photos : photo_urls
                i++


app.listen port
console.log 'server running on port ' + port 