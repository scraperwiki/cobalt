nock   = require 'nock'

exports.success = (apikey) ->
  nock('https://scraperwiki.com')
    .get("/froth/check_key/#{apikey}")
    .reply 200, (JSON.stringify { org: 'kiteorg'}),
      { 'content-type': 'text/plain' }

exports.forbidden = ->
  nock('https://scraperwiki.com')
    .get("/froth/check_key/junk")
    .reply 403, (JSON.stringify { error: 'Forbidden'}),
      { 'content-type': 'text/plain' }

exports.no_api_key = ->
  nock('https://scraperwiki.com')
    .get("/froth/check_key/")
    .reply 403, (JSON.stringify { error: 'Forbidden'}),
      { 'content-type': 'text/plain' }
