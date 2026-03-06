# frozen_string_literal: true

require "async"
require "logger"

module Nanobotrb
  module Channels
    # Manages all channels: starts them, routes outbound messages to the correct channel.
    class Manager
      def initialize(bus:, config:)
        @bus = bus
        @config = config
        @channels = {}
        @logger = Logger.new($stdout, progname: "ChannelManager")
      end

      def register(channel)
        @channels[channel.name] = channel
        @logger.info("Registered channel: #{channel.name}")
      end

      # Start all registered channels and the outbound dispatcher
      def start_all
        Async do |task|
          # Start each channel
          @channels.each_value do |channel|
            task.async { channel.start }
          end

          # Dispatch outbound messages
          task.async { dispatch_outbound }
        end
      end

      def stop_all
        @channels.each_value(&:stop)
      end

      private

      def dispatch_outbound
        loop do
          message = @bus.consume_outbound
          channel = @channels[message.channel]

          if channel
            channel.send_message(
              chat_id: message.chat_id,
              content: message.content,
              reply_to: message.reply_to,
              media: message.media
            )
          else
            @logger.warn("No channel found for: #{message.channel}")
          end
        rescue StandardError => e
          @logger.error("Outbound dispatch error: #{e.message}")
        end
      end
    end
  end
end
