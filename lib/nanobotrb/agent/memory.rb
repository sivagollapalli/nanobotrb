# frozen_string_literal: true

require "fileutils"

module Nanobotrb
  module Agent
    # Two-layer persistent memory:
    # - MEMORY.md: Long-term facts (updated by LLM via save_memory tool)
    # - HISTORY.md: Grep-searchable timestamped log
    class Memory
      def initialize(memory_dir:)
        @memory_dir = memory_dir
        FileUtils.mkdir_p(@memory_dir)
      end

      def long_term
        read_file("MEMORY.md")
      end

      def history
        read_file("HISTORY.md")
      end

      def save_memory(content)
        write_file("MEMORY.md", content)
      end

      def append_history(entry)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M")
        File.open(history_path, "a") { |f| f.puts("## #{timestamp}\n\n#{entry}\n") }
      end

      private

      def memory_path
        File.join(@memory_dir, "MEMORY.md")
      end

      def history_path
        File.join(@memory_dir, "HISTORY.md")
      end

      def read_file(name)
        path = File.join(@memory_dir, name)
        File.exist?(path) ? File.read(path) : ""
      end

      def write_file(name, content)
        File.write(File.join(@memory_dir, name), content)
      end
    end
  end
end
