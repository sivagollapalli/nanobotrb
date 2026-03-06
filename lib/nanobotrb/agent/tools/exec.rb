# frozen_string_literal: true

require "open3"
require "timeout"

module Nanobotrb
  module Agent
    module Tools
      class Exec < Base
        DANGEROUS_COMMANDS = %w[rm rmdir mkfs dd format fdisk].freeze

        def initialize(timeout: 30)
          @timeout = timeout
        end

        def name = "exec"
        def description = "Execute a shell command and return its output"

        def parameters
          {
            type: "object",
            properties: {
              command: { type: "string", description: "Shell command to execute" }
            },
            required: ["command"]
          }
        end

        def execute(command:, **_)
          base_cmd = command.split(/\s+/).first&.downcase
          if DANGEROUS_COMMANDS.include?(base_cmd)
            return "Error: Command '#{base_cmd}' is blocked for safety"
          end

          Timeout.timeout(@timeout) do
            stdout, stderr, status = Open3.capture3(command)
            output = stdout.empty? ? stderr : stdout
            output = output[0...50_000] + "\n...(truncated)" if output.length > 50_000
            "Exit code: #{status.exitstatus}\n#{output}"
          end
        rescue Timeout::Error
          "Error: Command timed out after #{@timeout}s"
        rescue StandardError => e
          "Error executing command: #{e.message}"
        end
      end
    end
  end
end
