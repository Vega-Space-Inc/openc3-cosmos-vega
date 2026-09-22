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
# The plugin uses ONE key: the COSMOS secret VEGA_API_KEY (Admin / Secrets).
# It is read here, inside the interface, when each request is sent - so it
# never reaches a browser or the packet stream, and a value updated in
# Admin / Secrets takes effect on the next request with no restart. The
# `SECRET ENV` line in plugin.txt mounts the same secret as an environment
# variable; that is the fallback when the secret store cannot be read.
#
# One exception: a per-request token in the command's
# HTTP_HEADER_AUTHORIZATION parameter (OBFUSCATE'd, so masked in Command
# Sender and the text log) wins over the secret. The Timeline widget uses
# this for Vega's public demo key, so a fresh install shows data before the
# secret exists; a person can also send a command this way from Command
# Sender.
#
# NO KEY AT ALL (no token, no secret, no env var): the request is sent
# unauthenticated. Vega answers 401, which lands in ERROR_RESPONSE, so the
# status screen and the widget both show that the secret is missing. The
# unauthenticated paths (health check, demo key) don't care. A warning is
# logged once.
#
# WHY THE SCRUB: HttpAccessor stores HTTP_HEADER_* parameters in packet.extra,
# and after the interface write CommandDecomTopic / CommandTopic serialize
# packet.extra into the command logs. Packet#obfuscate does not touch DERIVED
# items or extra, so OBFUSCATE alone would still leak the token there. This
# protocol runs in write_data, between packet conversion and the HTTP call:
# it REMOVES the Authorization header from the packet's own extra (what gets
# logged) and returns a separate copy carrying the key (what gets sent).
#
# Usage (plugin.txt, under the INTERFACE):
#   PROTOCOL WRITE api_key_protocol.rb Authorization VEGA_API_KEY "Bearer "
#   SECRET ENV VEGA_API_KEY VEGA_API_KEY

require 'openc3/interfaces/protocols/protocol'
require 'openc3/utilities/logger'
require 'openc3/utilities/secrets'

module OpenC3
  class ApiKeyProtocol < Protocol
    # @param header [String] Request header to set
    # @param secret_name [String] COSMOS secret holding the key; also the environment variable SECRET ENV sets
    # @param prefix [String] Prepended to a bare key, e.g. "Bearer " for RFC 6750 bearer auth
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(header = 'Authorization', secret_name = 'VEGA_API_KEY', prefix = 'Bearer ', allow_empty_data = nil)
      super(allow_empty_data)
      @header = header.to_s
      @secret_name = secret_name.to_s
      @prefix = prefix.to_s
      @warned = false
    end

    # `extra` here IS packet.extra (convert_packet_to_data passes the same
    # object), so deleting the header from it scrubs the packet that will be
    # logged. The key goes out on a copy. Signature and return value match
    # Protocol#write_data: (data, extra).
    def write_data(data, extra = nil)
      extra ||= {}
      headers = extra['HTTP_HEADERS'] || {}
      token = take_header(headers, @header) # scrubbed from the logged packet
      key = token || secret_value
      wire_headers = headers.dup
      if key
        wire_headers[@header] = bearer(key)
        @warned = false # say so again if the secret goes away later
      elsif !@warned
        # Once, not every request: the periodic polls would flood the log
        @warned = true
        Logger.warn("No Vega API key: the #{@secret_name} secret does not exist (create it in Admin / Secrets) - requests go out unauthenticated and Vega will answer 401")
      end
      return super(data, extra.merge('HTTP_HEADERS' => wire_headers))
    end

    # Removes header `name` from `headers` and returns its value, or nil when
    # absent or blank. HttpAccessor stores HTTP_HEADER_<NAME> parameters under
    # the lower-cased name ('authorization'), so match case-insensitively -
    # header names are case-insensitive on the wire anyway.
    def take_header(headers, name)
      stored = headers.keys.find { |k| k.to_s.casecmp?(name) }
      return nil unless stored
      value = headers.delete(stored).to_s.strip
      value.empty? ? nil : value
    end

    # Accepts a bare key as well as a full "Bearer ..." value
    def bearer(key)
      key = key.to_s.strip
      return key if @prefix.empty? or key.downcase.start_with?(@prefix.strip.downcase)
      @prefix + key
    end

    # The VEGA_API_KEY secret, read from the secret store on every request (a
    # Redis lookup) so an update in Admin / Secrets takes effect at once; the
    # environment variable SECRET ENV mounted at start is the fallback. nil
    # when neither holds a value.
    def secret_value
      value = nil
      begin
        value = Secrets.getClient.get(@secret_name, scope: ENV.fetch('OPENC3_SCOPE', 'DEFAULT')).to_s.strip
      rescue => e
        Logger.warn("Could not read the #{@secret_name} secret (#{e.class}: #{e.message}); using the environment variable") unless @store_warned
        @store_warned = true
      end
      value = ENV[@secret_name].to_s.strip if value.nil? or value.empty?
      value.empty? ? nil : value
    end
  end
end
