should = require 'should'
sinon = require 'sinon'
redis = require 'redis'
child_process = require 'child_process'

describe 'Box update subscriptions', ->
  before ->
    @serv = require 'serv'
    @psubSpy = sinon.spy @serv.redisClient, 'psubscribe'

  after ->
    @serv.redisClient.psubscribe.restore()

  it 'subscribes to the correct channel pattern', ->
    @psubSpy.called.should.be.true
    @psubSpy.calledWith("#{process.env.NODE_ENV}.cobalt.dataset.*.update")
      .should.be.true

  context 'when we receive a message on the box channel', ->
    before ->
      testClient = redis.createClient()
      testClient.on 'ready', ->
        message = JSON.stringify
          boxes: ['foo', 'bar']
          message: "We have updated"
        testClient.publish "#{process.env.NODE_ENV}.cobalt.dataset.d1000.update", message

    before ->
      @execStub = sinon.stub child_process, 'exec'

    it 'execs the update hook in the boxes', (done) ->
      setTimeout =>
        fooExeced = @execStub.calledWith "su foo -l -c ~/tool/hooks/update"
        barExeced = @execStub.calledWith "su bar -l -c ~/tool/hooks/update"

        fooExeced.should.be.true
        barExeced.should.be.true
        done()
      , 200
