# frozen_string_literal: true

module Nanobotrb
  module Agent
    class ContextBuilder
      SYSTEM_TEMPLATE = <<~PROMPT
        You are nanobot, a helpful AI assistant.

        ## Runtime Info
        - Time: %<time>s
        - Platform: Ruby/nanobotrb v%<version>s

        ## Guidelines
        - Be helpful, concise, and accurate
        - Use tools when needed to accomplish tasks
        - If you don't know something, say so

        %<memory>s
      PROMPT

      def initialize(memory:, config:)
        @memory = memory
        @config = config
      end

      def build_system_prompt
        memory_section = @memory.long_term.empty? ? "" : "## Long-term Memory\n\n#{@memory.long_term}"

        format(
          SYSTEM_TEMPLATE,
          time: Time.now.strftime("%Y-%m-%d %H:%M %Z"),
          version: Nanobotrb::VERSION,
          memory: memory_section
        )
      end

      def build_messages(session_history:, user_content:, channel: nil, chat_id: nil)
        messages = [{ role: "system", content: build_system_prompt }]

        # Add conversation history
        session_history.each do |msg|
          messages << { role: msg["role"], content: msg["content"] }
        end

        # Add current user message with runtime context
        runtime_ctx = []
        runtime_ctx << "[channel: #{channel}]" if channel
        runtime_ctx << "[chat: #{chat_id}]" if chat_id
        runtime_ctx << "[time: #{Time.now.strftime("%Y-%m-%d %H:%M %Z")}]"

        user_msg = runtime_ctx.any? ? "#{runtime_ctx.join(" ")}\n\n#{user_content}" : user_content
        messages << { role: "user", content: user_msg }

        messages
      end
    end
  end
end
