express     = require 'express'
path        = require 'path'
fs          = require 'fs'
util        = require 'util'
stylus      = require 'stylus'
http        = require 'http'
request     = require 'request'
app         = express.createServer()
port        = process.env.PORT || 3001

#app.use require('connect-assets')(src : 'public')

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

find_fb_photo = (req, res, next) ->
    rando       = Math.floor(Math.random() * 10000000) + 1
    fb_req      = "https://graph.facebook.com/#{rando}?fields=picture"
    res.uid     = rando
    request fb_req, (error, response, body) ->
        res.pic = JSON.parse(response.body).picture
        next()

app.get '/', find_fb_photo, (req, res, next) ->

    ###
    request.get res.pic, (err, data) ->
        fs.writeFile "#{__dirname}/public/fb_images/#{res.uid}.gif", data, 'binary', (err) ->
            res.contentType 'image/gif'
            res.end "#{__dirname}/public/fb_images/#{res.uid}.gif", 'binary'
    ###
    
    piped = request(res.pic).pipe(fs.createWriteStream("#{__dirname}/public/fb_images/#{res.uid}.gif"))
    setTimeout (->
        img = fs.readFileSync piped.path
        res.contentType 'image/gif'
        res.end img, 'binary'
    ), 1500

app.listen port
console.log 'server running on port ' + port 