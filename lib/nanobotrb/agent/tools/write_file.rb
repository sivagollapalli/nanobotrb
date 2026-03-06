# frozen_string_literal: true

require "fileutils"

module Nanobotrb
  module Agent
    module Tools
      class WriteFile < Base
        def name = "write_file"
        def description = "Write content to a file (creates directories as needed)"

        def parameters
          {
            type: "object",
            properties: {
              path: { type: "string", description: "Path to the file to write" },
              content: { type: "string", description: "Content to write" }
            },
            required: %w[path content]
          }
        end

        def execute(path:, content:, **_)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
          "Successfully wrote #{content.length} bytes to #{path}"
        rescue StandardError => e
          "Error writing file: #{e.message}"
        end
      end
    end
  end
end
