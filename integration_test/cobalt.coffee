# cobalt.coffee

http = require 'http'
# https://github.com/mikeal/request
request = require 'request'
should = require 'should'
_ = require 'underscore'

baseurl = 'http://integration-test-0.scraperwiki.net/'

describe 'Integration testing', ->
  describe 'When I use the http API', ->
    it 'GET / works'
    it 'I can create a box'
    it 'I can add an ssh key'
    it 'the CORS headers are present'
  describe 'When I login to my box', ->
    it 'SSH works'
    it 'I can see my readme.md'
    it 'I can see my git repo'
    it 'I cannot see any other box'
  describe 'When I publish some files', ->
    it 'I can see a root index page'
    it 'I can see normal files'
    it 'I can see an index page for subdirectories'
    it 'I can follow my own symlinks'
    it 'I cannot follow naughty symlinks'
    describe 'as JSONP', ->
      it 'the JSONP thing works'
    describe 'as JSON', ->
      it 'the CORS headers are still present'
  describe 'When I get data', ->
    it 'I can use the SQL web API'
   
