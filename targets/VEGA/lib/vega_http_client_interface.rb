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


# HttpClientInterface that can recover from an in-process disconnect.
#
# COSMOS's HttpClientInterface (7.3.1) creates its response queue once, in
# initialize. Its disconnect pushes a nil onto that queue so a blocked
# read_interface returns and the read thread exits - but connect never drains
# the queue. So after ANY disconnect that is not a process restart (a write
# error when the network drops, an HTTP failure, an operator toggling the
# interface), the next connect succeeds and the read thread immediately pops
# the stale nil, which COSMOS treats as "read_interface requested disconnect":
# disconnect again, push another nil, reconnect in 5s, repeat forever. Seen
# 2026-09-10 after a laptop network change: 20 minutes of DNS failures, then
# a Connect / Success / Lost cycle every 5s until the process was restarted.
#
# Draining the queue on connect is the fix for that. The other addition:
# each response packet carries the REQUEST's HTTP_PATH in its extra, so the
# ERROR_RESPONSE packet (shared by every failed request, background polls
# included) can say which request failed - the Timeline widget matches
# errors to its own requests by it. The stock interface keeps the request's
# extra only until it has picked the response packet, then drops it.
#
# plugin.txt:
#   INTERFACE VEGA_INT vega_http_client_interface.rb <host> <port> <protocol> <write_timeout> <read_timeout> <connect_timeout>

require 'openc3/interfaces/http_client_interface'

module OpenC3
  class VegaHttpClientInterface < HttpClientInterface
    def connect
      # Discard anything left from a previous session - in practice the nil
      # that disconnect pushes - so the read thread starts on a clean queue.
      @response_queue.pop while @response_queue.length > 0
      super
    end

    # HttpAccessor reads an HTTP_PATH item from packet.extra['HTTP_PATH'], and
    # the stock method sets packet.extra to this very hash (minus
    # HTTP_REQUEST), so copying the path across is all it takes.
    def convert_data_to_packet(data, extra = nil)
      request = extra && extra['HTTP_REQUEST'] && extra['HTTP_REQUEST'][1]
      extra['HTTP_PATH'] = request['HTTP_PATH'].to_s if request and request['HTTP_PATH']
      super
    end
  end
end
