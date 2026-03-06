# frozen_string_literal: true

module Nanobotrb
  module Agent
    module Tools
      class Registry
        def initialize
          @tools = {}
        end

        def register(tool)
          @tools[tool.name] = tool
        end

        def get(name)
          @tools[name]
        end

        def definitions
          @tools.values.map(&:to_definition)
        end

        def execute(name, **args)
          tool = @tools[name]
          raise Error, "Unknown tool: #{name}" unless tool

          tool.execute(**args)
        end

        def tool_names
          @tools.keys
        end
      end
    end
  end
end
