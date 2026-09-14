# encoding: ascii-8bit

# Copyright 2026 Vega Space, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from Vega Space, Inc.


# Puts the Vega frontend API key on the wire without letting it into any
# COSMOS log or store.
#
# TWO SOURCES, in priority order:
#   1. A per-request token in the command's HTTP_HEADER_AUTHORIZATION
#      parameter. The Timeline widget sends the user's own key this way (it
#      lives only in that user's browser). The parameter is OBFUSCATE'd, which
#      masks it in Command Sender and in the text command log.
#   2. The VEGA_API_KEY environment variable, mounted by `SECRET ENV` in
#      plugin.txt from Admin / Secrets. Used by the background polls and by any
#      command sent without a token.
#
# NO KEY AT ALL: an authenticated request is DROPPED (:STOP) rather than
# sent. Without the secret, the background PERIODIC_CMD polls have nothing to
# authenticate with; sending them anyway just buys a 401 every period into
# ERROR_RESPONSE - a stream of failures for a request that could never have
# succeeded. The one unauthenticated path
# (the health check) still goes out. A warning is logged once.
#
# WHY THE SCRUB: HttpAccessor stores HTTP_HEADER_* parameters in packet.extra,
# and after the interface write CommandDecomTopic / CommandTopic serialize
# packet.extra into the command logs. Packet#obfuscate does not touch DERIVED
# items or extra, so OBFUSCATE alone would still leak the token there. This
# protocol runs in write_data, between packet conversion and the HTTP call:
# it REMOVES the Authorization header from the packet's own extra (what gets
# logged) and returns a separate copy carrying the token (what gets sent).
#
# Usage (plugin.txt, under the INTERFACE):
#   PROTOCOL WRITE api_key_protocol.rb Authorization VEGA_API_KEY "Bearer "
#   SECRET ENV VEGA_API_KEY VEGA_API_KEY

require 'openc3/interfaces/protocols/protocol'
require 'openc3/utilities/logger'

module OpenC3
  class ApiKeyProtocol < Protocol
    # @param header [String] Request header to set
    # @param env_var [String] Environment variable holding the fallback key (set by SECRET ENV)
    # @param prefix [String] Prepended to a bare key, e.g. "Bearer " for RFC 6750 bearer auth
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(header = 'Authorization', env_var = 'VEGA_API_KEY', prefix = 'Bearer ', allow_empty_data = nil)
      super(allow_empty_data)
      @header = header.to_s
      @env_var = env_var.to_s
      @prefix = prefix.to_s
      @warned = false
    end

    # Paths that need no key and are always sent (GET_HEALTH's
    # /api/v1/health_check; /health kept for older API builds).
    PUBLIC_PATH_SUFFIXES = ['/health_check', '/health', '/demo_key'].freeze

    def public_request?(extra)
      uri = extra['HTTP_URI'].to_s
      path = uri.split('?', 2).first.to_s
      PUBLIC_PATH_SUFFIXES.any? { |suffix| path.end_with?(suffix) }
    end

    # `extra` here IS packet.extra (convert_packet_to_data passes the same
    # object), so deleting the header from it scrubs the packet that will be
    # logged. The token goes out on a copy. Signature and return value match
    # Protocol#write_data: (data, extra).
    def write_data(data, extra = nil)
      extra ||= {}
      headers = extra['HTTP_HEADERS'] || {}
      # HttpAccessor stores HTTP_HEADER_<NAME> parameters under the
      # lower-cased name ('authorization'), so match case-insensitively -
      # header names are case-insensitive on the wire anyway.
      stored = headers.keys.find { |k| k.to_s.casecmp?(@header) }
      token = stored ? headers.delete(stored) : nil # scrubbed from the logged packet
      token = nil if token.nil? or token.to_s.strip.empty?

      wire_headers = headers.dup
      if token
        token = token.to_s.strip
        # Accept a bare key as well as a full "Bearer ..." value
        token = @prefix + token unless @prefix.empty? or token.downcase.start_with?(@prefix.strip.downcase)
        wire_headers[@header] = token
      else
        key = ENV[@env_var]
        if key and !key.empty?
          wire_headers[@header] = @prefix + key
        elsif !public_request?(extra)
          unless @warned
            # Warn once per instance so the periodic polls don't flood the log
            @warned = true
            Logger.warn("No API key and #{@env_var} is not set - authenticated requests are dropped until a key is entered in the Timeline widget or the secret is created in Admin / Secrets (then restart the interface)")
          end
          return :STOP
        end
      end
      return super(data, extra.merge('HTTP_HEADERS' => wire_headers))
    end
  end
end
