should = require 'should'
sinon = require 'sinon'
redis = require 'redis'
child_process = require 'child_process'

describe 'Box update subscriptions', ->
  context 'when we receive a message on the box channel', ->
    before (done) ->
      delete require.cache.server
      @server = require 'server'
      @psubSpy = sinon.spy @server.redisClient, 'psubscribe'
      @server.start (err) ->
        done()

    after (done) ->
      # @serv.redisClient.psubscribe.restore()
      @server.stop (err) ->
        done()

    it 'subscribes to the correct channel pattern', ->
      @psubSpy.called.should.be.true
      @psubSpy.calledWith("#{process.env.NODE_ENV}.cobalt.dataset.*.update")
        .should.be.true

    before ->
      testClient = redis.createClient()
      testClient.on 'ready', ->
        message = JSON.stringify
          boxes: ['foo', 'bar']
          message: "We have updated"
          origin:
            box: "baz"
            boxServer: "bazServer"
            boxJSON:
              publish_token: "bazToken"
        channel = "#{process.env.NODE_ENV}.cobalt.dataset.d1000.update"
        testClient.publish channel, message

    before ->
      @execStub = sinon.stub child_process, 'exec'

    it 'execs the update hook in the boxes', (done) ->
      setTimeout =>

        fooExeced = @execStub.calledWith '''su foo -l -c '/home/tool/hooks/update "$@"' -- /home/tool/hooks/update https://bazServer/baz/bazToken'''
        barExeced = @execStub.calledWith '''su bar -l -c '/home/tool/hooks/update "$@"' -- /home/tool/hooks/update https://bazServer/baz/bazToken'''

        fooExeced.should.be.true
        barExeced.should.be.true
        done()
      , 200
