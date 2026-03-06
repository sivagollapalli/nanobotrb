# frozen_string_literal: true

module Nanobotrb
  module Agent
    module Tools
      class Base
        def name
          raise NotImplementedError
        end

        def description
          raise NotImplementedError
        end

        # Returns JSON Schema hash for parameters
        def parameters
          raise NotImplementedError
        end

        # Execute the tool with given arguments, returns string result
        def execute(**args)
          raise NotImplementedError
        end

        # Convert to RubyLLM-compatible tool definition
        def to_definition
          {
            name: name,
            description: description,
            parameters: parameters
          }
        end
      end
    end
  end
end
