# frozen_string_literal: true

require "async"
require "async/condition"

module Nanobotrb
  module Bus
    # Async message bus with two queues: inbound (channel→agent) and outbound (agent→channel).
    # Uses Async::Condition for signaling and a simple array-based queue.
    class MessageBus
      def initialize
        @inbound = []
        @outbound = []
        @inbound_condition = Async::Condition.new
        @outbound_condition = Async::Condition.new
      end

      def publish_inbound(message)
        @inbound.push(message)
        @inbound_condition.signal
      end

      def publish_outbound(message)
        @outbound.push(message)
        @outbound_condition.signal
      end

      # Blocks until an inbound message is available
      def consume_inbound
        while @inbound.empty?
          @inbound_condition.wait
        end
        @inbound.shift
      end

      # Blocks until an outbound message is available
      def consume_outbound
        while @outbound.empty?
          @outbound_condition.wait
        end
        @outbound.shift
      end
    end
  end
end
