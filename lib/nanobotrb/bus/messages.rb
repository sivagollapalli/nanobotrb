# frozen_string_literal: true

module Nanobotrb
  module Bus
    InboundMessage = Data.define(:channel, :sender_id, :chat_id, :content, :media, :metadata) do
      def initialize(channel:, sender_id:, chat_id:, content:, media: nil, metadata: {})
        super
      end
    end

    OutboundMessage = Data.define(:channel, :chat_id, :content, :reply_to, :media) do
      def initialize(channel:, chat_id:, content:, reply_to: nil, media: nil)
        super
      end
    end
  end
end
