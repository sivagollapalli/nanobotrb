# frozen_string_literal: true

module Nanobotrb
  module Channels
    class Base
      attr_reader :name, :bus, :config

      def initialize(name:, bus:, config:)
        @name = name
        @bus = bus
        @config = config
        @allow_from = channel_config["allow_from"] || []
      end

      def start
        raise NotImplementedError
      end

      def stop
        raise NotImplementedError
      end

      def send_message(chat_id:, content:, reply_to: nil, media: nil)
        raise NotImplementedError
      end

      def allowed?(sender_id)
        return false if @allow_from.empty?
        return true if @allow_from.include?("*")

        @allow_from.include?(sender_id.to_s)
      end

      private

      def channel_config
        @config.channel_config(@name)
      end

      def publish_inbound(sender_id:, chat_id:, content:, media: nil, metadata: {})
        unless allowed?(sender_id)
          warn "[#{@name}] Denied message from #{sender_id}"
          return
        end

        message = Bus::InboundMessage.new(
          channel: @name,
          sender_id: sender_id.to_s,
          chat_id: chat_id.to_s,
          content: content,
          media: media,
          metadata: metadata
        )
        @bus.publish_inbound(message)
      end
    end
  end
end
