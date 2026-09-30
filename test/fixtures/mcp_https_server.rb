# frozen_string_literal: true

require 'json'
require 'openssl'
require 'tempfile'
require 'webrick'
require 'webrick/https'

# riffer takes HTTPS MCP endpoints only, so the server presents a self-signed
# certificate for 127.0.0.1 that the client is made to trust through
# SSL_CERT_FILE, which faraday's default certificate store reads.
class McpHttpsServer
  class Servlet < WEBrick::HTTPServlet::AbstractServlet # rubocop:disable Rig/NoInheritance -- WEBrick mounts servlet subclasses only
    def initialize(server, mcp)
      super(server)
      @mcp = mcp
    end

    def service(request, response)
      @mcp.handle(request, response)
    end
  end

  TOOLS = [
    {
      name: 'echo',
      description: 'Echoes its text back.',
      inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] }
    },
    {
      name: 'token',
      description: 'Reports the X-Token request header.',
      inputSchema: { type: 'object', properties: {} }
    }
  ].freeze

  def initialize
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = self_signed(key)
    @ca_file = Tempfile.new(['mcp-https-server', '.pem']).tap do |file|
      file.write(certificate.to_pem)
      file.flush
    end
    @server = WEBrick::HTTPServer.new(
      Port: 0,
      BindAddress: '127.0.0.1',
      SSLEnable: true,
      SSLCertificate: certificate,
      SSLPrivateKey: key,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
    %w[/mcp /alt].each { |path| @server.mount(path, Servlet, self) }
    @thread = Thread.new { @server.start }
  end

  def ca_file
    @ca_file.path
  end

  def url(path = 'mcp')
    "https://127.0.0.1:#{@server.config[:Port]}/#{path}"
  end

  def stop
    @server.shutdown
    @thread.join
    @ca_file.close!
  end

  def handle(request, response)
    message = JSON.parse(request.body)
    return response.status = 202 unless message.key?('id')

    case message['method']
    when 'tools/list' then json(response, message, result: { tools: TOOLS })
    when 'tools/call' then event_stream(response, message, result: call_tool(request, message['params']))
    else json(response, message, error: { code: -32_601, message: "Method not found: #{message['method']}" })
    end
  end

  private

  def self_signed(key)
    name = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = name
    certificate.issuer = name
    certificate.public_key = key.public_key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new(certificate, certificate)
    certificate.add_extension(extensions.create_extension('basicConstraints', 'CA:TRUE', true))
    certificate.add_extension(extensions.create_extension('subjectAltName', 'IP:127.0.0.1'))
    certificate.sign(key, OpenSSL::Digest.new('SHA256'))
    certificate
  end

  def call_tool(request, params)
    text = params['name'] == 'token' ? request['X-Token'] : params.dig('arguments', 'text')
    { content: [{ type: 'text', text: text }] }
  end

  def json(response, message, **outcome)
    response['Content-Type'] = 'application/json'
    response.body = { jsonrpc: '2.0', id: message['id'], **outcome }.to_json
  end

  def event_stream(response, message, **outcome)
    response['Content-Type'] = 'text/event-stream'
    response.body = "event: message\ndata: #{{ jsonrpc: '2.0', id: message['id'], **outcome }.to_json}\n\n"
  end
end
