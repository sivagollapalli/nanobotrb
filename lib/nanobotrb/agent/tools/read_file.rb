# frozen_string_literal: true

module Nanobotrb
  module Agent
    module Tools
      class ReadFile < Base
        def name = "read_file"
        def description = "Read the contents of a file"

        def parameters
          {
            type: "object",
            properties: {
              path: { type: "string", description: "Path to the file to read" }
            },
            required: ["path"]
          }
        end

        def execute(path:, **_)
          return "Error: File not found: #{path}" unless File.exist?(path)

          content = File.read(path)
          content.length > 100_000 ? content[0...100_000] + "\n...(truncated)" : content
        rescue StandardError => e
          "Error reading file: #{e.message}"
        end
      end
    end
  end
end
