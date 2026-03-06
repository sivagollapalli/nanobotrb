# frozen_string_literal: true

require "telegram/bot"
require "logger"

module Nanobotrb
  module Channels
    class Telegram < Base
      def initialize(bus:, config:)
        super(name: "telegram", bus: bus, config: config)
        @token = channel_config["token"] || ENV["TELEGRAM_BOT_TOKEN"]
        @logger = Logger.new($stdout, progname: "TelegramChannel")
        @bot = nil
        @running = false
      end

      def start
        unless @token
          @logger.error("No Telegram bot token configured")
          return
        end

        @running = true
        @logger.info("Starting Telegram channel...")

        ::Telegram::Bot::Client.run(@token) do |bot|
          @bot = bot
          @logger.info("Telegram bot connected")

          bot.listen do |message|
            break unless @running

            handle_message(message)
          end
        end
      rescue StandardError => e
        @logger.error("Telegram error: #{e.message}")
        retry if @running
      end

      def stop
        @running = false
        @logger.info("Telegram channel stopped")
      end

      def send_message(chat_id:, content:, reply_to: nil, media: nil)
        return unless @bot

        # Split long messages (Telegram limit: 4096 chars)
        chunks = split_message(content, 4096)
        chunks.each do |chunk|
          opts = { chat_id: chat_id, text: chunk, parse_mode: "Markdown" }
          opts[:reply_to_message_id] = reply_to if reply_to
          @bot.api.send_message(**opts)
        rescue ::Telegram::Bot::Exceptions::ResponseError => e
          # Retry without Markdown if parsing fails
          if e.message.include?("can't parse")
            @bot.api.send_message(chat_id: chat_id, text: chunk)
          else
            @logger.error("Telegram send error: #{e.message}")
          end
        end
      end

      private

      def handle_message(message)
        return unless message.is_a?(::Telegram::Bot::Types::Message)
        return unless message.text

        sender_id = message.from&.id&.to_s
        chat_id = message.chat&.id&.to_s
        content = message.text

        @logger.info("Received from #{sender_id} in #{chat_id}: #{content[0..50]}...")

        publish_inbound(
          sender_id: sender_id,
          chat_id: chat_id,
          content: content,
          metadata: {
            "message_id" => message.message_id,
            "username" => message.from&.username,
            "first_name" => message.from&.first_name
          }
        )
      end

      def split_message(text, max_length)
        return [text] if text.length <= max_length

        chunks = []
        remaining = text
        while remaining.length > max_length
          # Try to split at a newline
          split_idx = remaining.rindex("\n", max_length) || max_length
          chunks << remaining[0...split_idx]
          remaining = remaining[split_idx..].lstrip
        end
        chunks << remaining unless remaining.empty?
        chunks
      end
    end
  end
end
