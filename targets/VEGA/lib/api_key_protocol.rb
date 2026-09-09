# encoding: ascii-8bit

# Injects the Vega frontend API key into every outgoing HTTP request.
#
# WHY THIS LIVES IN A WRITE PROTOCOL rather than in the command definition:
# HttpClientInterface builds the request headers from the command packet's
# HTTP_HEADER_* parameters, and that packet is exactly what the command log,
# the command CVT, Command Sender and every other tool see. A key baked into a
# PARAMETER (or supplied as one at send time) is therefore written in plain
# text to every command log entry. Protocol#write_data runs AFTER the packet
# has been converted to data/extra and logged, so a header added here reaches
# the wire but never the log, the packet definition, a setting, or any tool.
#
# The key itself is delivered by `SECRET ENV VEGA_API_KEY VEGA_API_KEY` in
# plugin.txt, which mounts the Admin / Secrets entry as an environment
# variable inside the interface container. Nothing in the plugin
# configuration carries it.
#
# Usage (plugin.txt, under the INTERFACE):
#   PROTOCOL WRITE api_key_protocol.rb Authorization VEGA_API_KEY "Bearer "
#   SECRET ENV VEGA_API_KEY VEGA_API_KEY

require 'openc3/interfaces/protocols/protocol'
require 'openc3/utilities/logger'

module OpenC3
  class ApiKeyProtocol < Protocol
    # @param header [String] Request header to set
    # @param env_var [String] Environment variable holding the key (set by SECRET ENV)
    # @param prefix [String] Prepended to the key, e.g. "Bearer " for RFC 6750 bearer auth
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(header = 'Authorization', env_var = 'VEGA_API_KEY', prefix = 'Bearer ', allow_empty_data = nil)
      super(allow_empty_data)
      @header = header.to_s
      @env_var = env_var.to_s
      @prefix = prefix.to_s
      @warned = false
    end

    # Called after the packet has been converted to data / extra (and after the
    # command was logged), so the key ends up in the request headers only.
    # Signature and return value match Protocol#write_data: (data, extra).
    def write_data(data, extra = nil)
      api_key = ENV[@env_var]
      if api_key and !api_key.empty?
        extra ||= {}
        headers = extra['HTTP_HEADERS']
        unless headers
          headers = {}
          extra['HTTP_HEADERS'] = headers
        end
        headers[@header] = @prefix + api_key
      elsif !@warned
        # Warn once per instance so the periodic polls don't flood the log
        @warned = true
        Logger.warn("#{@env_var} not set - create it in Admin / Secrets and restart VEGA_INT")
      end
      return super(data, extra)
    end
  end
end
