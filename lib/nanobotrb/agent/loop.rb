# frozen_string_literal: true

require "async"
require "logger"
require "json"

module Nanobotrb
  module Agent
    class Loop
      SPECIAL_COMMANDS = %w[/new /stop /help].freeze

      attr_reader :config, :bus, :session_manager, :memory, :context_builder, :tool_registry, :provider

      def initialize(config:, bus:, provider: nil)
        @config = config
        @bus = bus
        @logger = Logger.new($stdout, progname: "AgentLoop")
        @session_manager = Session::Manager.new(sessions_dir: config.sessions_dir)
        @memory = Memory.new(memory_dir: config.memory_dir)
        @context_builder = ContextBuilder.new(memory: @memory, config: config)
        @tool_registry = Tools::Registry.new
        @provider = provider || Providers::RubyLLMProvider.new(config: config)
        @running = false

        register_default_tools!
      end

      # Start the async consumer loop (for gateway mode)
      def run
        @running = true
        @logger.info("AgentLoop started")

        while @running
          message = @bus.consume_inbound
          process_message(message)
        end
      end

      def stop
        @running = false
        @logger.info("AgentLoop stopped")
      end

      # Process a single message directly (for CLI mode)
      def process_direct(content, channel: "cli", sender_id: "user", chat_id: "default")
        message = Bus::InboundMessage.new(
          channel: channel, sender_id: sender_id,
          chat_id: chat_id, content: content
        )
        process_message(message)
      end

      private

      def register_default_tools!
        @tool_registry.register(Tools::ReadFile.new)
        @tool_registry.register(Tools::WriteFile.new)
        @tool_registry.register(Tools::Exec.new(timeout: @config.dig("tools", "exec_timeout") || 30))
        @tool_registry.register(Tools::WebSearch.new(api_key: @config.dig("tools", "serpapi_key")))
      end

      def process_message(message)
        session = @session_manager.get(channel: message.channel, chat_id: message.chat_id)

        # Handle special commands
        case message.content.strip
        when "/new"
          session.clear!
          publish_response(message, "Session cleared. Starting fresh.")
          return
        when "/stop"
          stop
          publish_response(message, "Agent stopped.")
          return
        when "/help"
          publish_response(message, help_text)
          return
        end

        # Build context and call LLM
        messages = @context_builder.build_messages(
          session_history: session.get_history,
          user_content: message.content,
          channel: message.channel,
          chat_id: message.chat_id
        )

        # LLM call loop with tool execution
        response_content = llm_loop(messages)

        # Save turn to session
        session.append(role: "user", content: message.content)
        session.append(role: "assistant", content: response_content)

        # Check if memory consolidation is needed
        maybe_consolidate(session)

        # Publish response
        publish_response(message, response_content)

        response_content
      rescue StandardError => e
        @logger.error("Error processing message: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        error_msg = "Sorry, I encountered an error: #{e.message}"
        publish_response(message, error_msg)
        error_msg
      end

      def llm_loop(messages)
        iterations = 0
        max_iter = @config.max_iterations

        loop do
          iterations += 1
          if iterations > max_iter
            @logger.warn("Max iterations (#{max_iter}) reached")
            break
          end

          response = @provider.chat(
            messages: messages,
            tools: @tool_registry.definitions,
            model: @config.model,
            max_tokens: @config.max_tokens,
            temperature: @config.temperature
          )

          # If no tool calls, we're done
          if response.tool_calls.nil? || response.tool_calls.empty?
            return response.content || "I'm not sure how to respond to that."
          end

          # Execute tool calls
          messages << { role: "assistant", content: response.content, tool_calls: response.tool_calls }

          response.tool_calls.each do |tool_call|
            tool_name = tool_call["name"] || tool_call[:name]
            args = tool_call["arguments"] || tool_call[:arguments] || {}
            args = JSON.parse(args) if args.is_a?(String)

            @logger.info("Executing tool: #{tool_name}")
            result = @tool_registry.execute(tool_name, **args.transform_keys(&:to_sym))

            messages << {
              role: "tool",
              content: result.to_s,
              tool_call_id: tool_call["id"] || tool_call[:id]
            }
          end
        end

        "I reached the maximum number of iterations. Here's what I have so far."
      end

      def maybe_consolidate(session)
        unconsolidated = session.unconsolidated_messages
        return unless unconsolidated && unconsolidated.length >= @config.memory_window

        @logger.info("Triggering memory consolidation for session #{session.key}")
        # Ask LLM to consolidate
        consolidation_prompt = <<~PROMPT
          Summarize the following conversation into a brief history entry.
          Also extract any important long-term facts to remember.

          Conversation:
          #{unconsolidated.map { |m| "#{m["role"]}: #{m["content"]}" }.join("\n\n")}
        PROMPT

        response = @provider.chat(
          messages: [
            { role: "system", content: "You are a memory consolidation assistant. Summarize conversations concisely." },
            { role: "user", content: consolidation_prompt }
          ]
        )

        if response.content
          @memory.append_history(response.content)
          session.update_consolidated(session.messages.length)
        end
      rescue StandardError => e
        @logger.error("Memory consolidation failed: #{e.message}")
      end

      def publish_response(inbound_message, content)
        outbound = Bus::OutboundMessage.new(
          channel: inbound_message.channel,
          chat_id: inbound_message.chat_id,
          content: content
        )
        @bus.publish_outbound(outbound)
      end

      def help_text
        <<~HELP
          Available commands:
          /new   - Start a new conversation
          /stop  - Stop the agent
          /help  - Show this help message

          Available tools: #{@tool_registry.tool_names.join(", ")}
        HELP
      end
    end
  end
end
