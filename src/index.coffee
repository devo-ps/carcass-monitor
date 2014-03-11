debug = require('debug')('carcass:monitor')

_ = require('highland')
require('highland-array')
carcass = require('carcass')
ForeverMonitor = require('forever-monitor').Monitor

###*
 * Monitor.
###
module.exports = class Monitor
    constructor: -> @initialize(arguments...)

carcass.mixable(Monitor)
Monitor::mixin(carcass.proto.uid)
Monitor::mixin(carcass.proto.stack)

Monitor::initialize = (options) ->
    @id(options)
    debug('initializing monitor %s.', @id())
    @children = []
    return @

###*
 * Start the monitor(s).
###
Monitor::start = (done) ->
    done ?= ->
    cb = _.wrapCallback(startOne)
    returned = false
    _done = ->
        return if returned
        returned = true
        done(arguments...)
    _(@stack()).flatMap(cb).stopOnError(_done).once('end', _done).each((child) =>
        @children.push(child)
    )
    return @

###*
 * Close the monitor(s).
###
Monitor::close = (done) ->
    done ?= ->
    cb = _.wrapCallback(closeOne)
    @children.shiftToStream().flatMap(cb).errors(debug).once('end', done).resume()
    return @

###*
 * Start one item.
###
startOne = (item, done) ->
    # TODO: inherit env?
    # debug('process.env', process.env)
    child = new ForeverMonitor(item.script, carcass.Object.extend({
        max: 1,
        fork: true
    }, item))
    child.on('error', done)
    if item.startupMessage?
        # Wait for a startup message and unsubscribe the listener.
        onMsg = (msg) ->
            if msg?[item.startupMessage]?
                debug('received startup message: %s', item.startupMessage)
                child.removeListener('message', onMsg)
                done(null, child)
        child.on('message', onMsg)
     else
        child.once('start', -> done(null, child))
    child.start()

###*
 * Close one item.
###
closeOne = (child, done) ->
    # debug('child', child)
    return done() if not child.running
    child.on('exit', -> done())
    child.stop()
