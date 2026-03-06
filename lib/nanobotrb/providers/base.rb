# frozen_string_literal: true

module Nanobotrb
  module Providers
    LLMResponse = Data.define(:content, :tool_calls, :finish_reason, :usage) do
      def initialize(content: nil, tool_calls: [], finish_reason: nil, usage: {})
        super
      end
    end

    class Base
      def chat(messages:, tools: [], model: nil, max_tokens: nil, temperature: nil)
        raise NotImplementedError
      end

      def default_model
        raise NotImplementedError
      end
    end
  end
end
