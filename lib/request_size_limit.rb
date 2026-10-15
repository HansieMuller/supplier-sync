# Reject declared oversized uploads before Rack parses multipart form data.
# Public deployment also needs ingress limits for chunked/undeclared request bodies.
class RequestSizeLimit
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["CONTENT_LENGTH"].to_i > 600_000
      [413, { "content-type" => "text/plain" }, ["Request too large"]]
    else
      @app.call(env)
    end
  end
end
