express     = require 'express'
path        = require 'path'
fs          = require 'fs'
util        = require 'util'
stylus      = require 'stylus'
http        = require 'http'
request     = require 'request'
redis       = require 'redis'
knox        = require 'knox'
bootstrap   = require 'bootstrap-stylus'
app         = express.createServer()
port        = process.env.PORT || 3001
env         = process.env.environment || 'development'
fb_int      = 3000

if env == 'development' then fb_int = 3000

app.use require('connect-assets')()
    
app.set 'views', path.join __dirname, 'views'
app.set 'view engine', 'jade'

app.use express.static path.join __dirname, 'public'

redis_client    = redis.createClient(2586, '50.30.35.9')

redis_client.auth process.env.REDIS_PASS, (err) ->
    if err then console.error "#{err} could not authenticate with redis"
    if env != 'production'
        get_photo_int = setInterval (-> build_fb_photo() ), fb_int

knox_client     = knox.createClient
    key         : process.env.S3_KEY
    secret      : process.env.S3_SECRET
    bucket      : 'faceholder'

get_photo_int   = 0

build_fb_photo  = ->
    rando       = Math.floor(Math.random() * 1000000000) + 1
    fb_req      = "https://graph.facebook.com/#{rando}/picture?type=large"

    request
        method  : 'GET'
        url     : fb_req
        timeout : 1500
    , (err, resp, body) ->

        if err then console.error 'rate limiting from facebook.'

        if resp
            image_path = resp.socket.pair.cleartext._httpMessage.path

            if image_path == '/static-ak/rsrc.php/v2/yL/r/HsTZSDw4avx.gif' || image_path == '/static-ak/rsrc.php/v2/yp/r/yDnr5YfbJCH.gif'
                return false
            else
                piped = request("https://fbcdn-profile-a.akamaihd.net/#{image_path}").pipe(fs.createWriteStream("#{__dirname}/public/fb_images/#{rando}.jpg"))
                piped.on 'error', (pipe_err) ->
                    console.error 'could not write photo from facebook to file system'
                    console.error pipe_err
                piped.on 'close', ->
                    random = "#{rando}.jpg"

                    knox_client.putFile piped.path, random, (err, res) ->
                        if err
                            console.error 'error writing to s3 server'
                            console.error err
                        else
                            fs.unlink "#{__dirname}/public/fb_images/#{rando}.jpg", (delete_err) ->
                                if delete_err
                                    console.error 'could not clean up file'
                                    console.error delete_err
                            redis_client.lpush 'friends', rando, (redis_err, redis_res) ->
                                if redis_err
                                    console.error 'could not write to remote redis server'
                                    console.error redis_err


get_photo_url = (max, index, next) ->
    rando = Math.floor(Math.random() * max)
    redis_client.lindex 'friends', rando, (err, res) ->
        if err then console.error "could not find record in database #{err}"
        else next(res, index)


get_photo_count = (next) ->
    redis_client.llen 'friends', (err, res) ->
        if err then console.error "could not get record length from database #{err}"
        else next(res)



app.get '/', (req, res, next) ->
    if req.headers.referrer
        res.redirect '/pic'
    else
        res.redirect '/25'


    
app.get '/pic', (req, res, next) ->
    get_photo_count (photo_count) ->
        get_photo_url photo_count, 0, (url, index) ->
            res.redirect "https://s3.amazonaws.com/faceholder/#{url}.jpg"



fb_locales = JSON.parse(fs.readFileSync('./fb_locales.js','utf-8'))

app.get '/hubot', (req, res, next) ->
    get_photo_count (photo_count) ->
        get_photo_url photo_count, 0, (id, index) ->

            fb_req      = "https://graph.facebook.com/#{id}"

            request
                method  : 'GET'
                url     : fb_req
                timeout : 1500
            , (err, resp, body) ->

                fb_body = JSON.parse(body)
               
                locale == 'American'
                for location in fb_locales
                    if location.fb_code == fb_body.locale
                        locale = location.nationality

                console.log fb_body

                res.send
                    id          : fb_body.id
                    name        : fb_body.name
                    gender      : fb_body.gender
                    url         : fb_body.link
                    nationality : locale
                    image       : "https://s3.amazonaws.com/faceholder/#{id}.jpg"



app.get '/:number', (req, res, next) ->

    if req.params.number > 100 then res.render 'max'
    else if req.params.number == '1' then res.redirect '/pic'

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
console.log "server running on port #{port} in #{env} environment"