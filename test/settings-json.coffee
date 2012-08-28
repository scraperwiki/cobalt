describe "scraperwiki.json settings API", ->
  # should we stub the readfile to return a fixture?
  describe "GET /<box_name>/settings", ->
    it "errors if no API key specified"
    it "returns a valid JSON object"

  describe "POST /<box_name>/settings", ->
    it "gives errors for bad JSON"
    it "succeeds with good JSON"
    it "saves the scraperwiki.json"
