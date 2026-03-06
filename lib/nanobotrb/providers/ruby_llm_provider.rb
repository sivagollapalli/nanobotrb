# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Nanobotrb
  module Providers
    # Direct OpenAI-compatible HTTP provider with full tool-calling support.
    # Bypasses RubyLLM to avoid the "developer" role issue and to control
    # the tool-call flow ourselves (so our ToolRegistry executes the tools).
    class RubyLLMProvider < Base
      def initialize(config:)
        @config = config
        @api_key = ENV.fetch("ABACUS_KEY", nil) ||
                   config.dig("providers", "openai", "api_key") ||
                   ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = config.dig("providers", "openai", "api_base") ||
                    "https://routellm.abacus.ai/v1"
      end

      def chat(messages:, tools: [], model: nil, max_tokens: nil, temperature: nil)
        model_name = model || @config.model
        temp = temperature || @config.temperature
        max_tok = max_tokens || @config.max_tokens

        # Build the API messages — fold system into first user message
        api_messages = build_api_messages(messages)

        body = {
          model: model_name,
          messages: api_messages,
          temperature: temp,
          max_tokens: max_tok
        }

        # Add tools if present
        unless tools.empty?
          body[:tools] = tools.map do |t|
            {
              type: "function",
              function: {
                name: t[:name],
                description: t[:description],
                parameters: t[:parameters]
              }
            }
          end
        end

        response = post_chat(body)
        parse_response(response)
      rescue StandardError => e
        warn "LLM API error: #{e.message}"
        LLMResponse.new(content: "Error calling LLM: #{e.message}")
      end

      def default_model = "gemini-2.5-pro"

      private

      # Fold system prompt into the first user message to avoid "developer" role issues.
      # Passes user/assistant/tool messages through as-is.
      def build_api_messages(messages)
        system_msg = messages.find { |m| m[:role] == "system" }
        non_system = messages.reject { |m| m[:role] == "system" }

        api_msgs = []
        system_injected = false

        non_system.each do |msg|
          if !system_injected && msg[:role] == "user" && system_msg
            # Prepend system prompt to the first user message
            api_msgs << { role: "user", content: "#{system_msg[:content]}\n\n---\n\n#{msg[:content]}" }
            system_injected = true
          elsif msg[:role] == "assistant" && msg[:tool_calls]
            # Assistant message with tool calls
            api_msgs << {
              role: "assistant",
              content: msg[:content],
              tool_calls: msg[:tool_calls].map do |tc|
                {
                  id: tc["id"] || tc[:id],
                  type: "function",
                  function: {
                    name: tc["name"] || tc[:name],
                    arguments: (tc["arguments"] || tc[:arguments]).is_a?(String) ? (tc["arguments"] || tc[:arguments]) : JSON.generate(tc["arguments"] || tc[:arguments])
                  }
                }
              end
            }
          elsif msg[:role] == "tool"
            api_msgs << { role: "tool", content: msg[:content], tool_call_id: msg[:tool_call_id] }
          else
            api_msgs << { role: msg[:role], content: msg[:content] }
          end
        end

        # If no user message was found to inject system into, prepend as system role
        if !system_injected && system_msg
          api_msgs.unshift({ role: "system", content: system_msg[:content] })
        end

        api_msgs
      end

      def post_chat(body)
        uri = URI("#{@api_base}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request.body = JSON.generate(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            response.body
          end
          raise "API returned #{response.code}: #{error_body}"
        end

        JSON.parse(response.body)
      end

      def parse_response(data)
        choice = data.dig("choices", 0)
        return LLMResponse.new unless choice

        message = choice["message"]
        content = message["content"]
        finish_reason = choice["finish_reason"]
        usage = data["usage"] || {}

        tool_calls = nil
        if message["tool_calls"]
          tool_calls = message["tool_calls"].map do |tc|
            {
              "id" => tc["id"],
              "name" => tc.dig("function", "name"),
              "arguments" => tc.dig("function", "arguments")
            }
          end
        end

        LLMResponse.new(
          content: content,
          tool_calls: tool_calls || [],
          finish_reason: finish_reason,
          usage: usage
        )
      end
    end
  end
end
