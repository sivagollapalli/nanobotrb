# frozen_string_literal: true

require "json"
require "fileutils"

module Nanobotrb
  module Session
    class Session
      attr_reader :key, :messages, :last_consolidated

      def initialize(key:, dir:)
        @key = key
        @dir = dir
        @messages = []
        @last_consolidated = 0
        load!
      end

      def append(role:, content:, tool_calls: nil, tool_call_id: nil)
        entry = { "role" => role, "content" => content, "timestamp" => Time.now.iso8601 }
        entry["tool_calls"] = tool_calls if tool_calls
        entry["tool_call_id"] = tool_call_id if tool_call_id
        @messages << entry
        persist_entry(entry)
        entry
      end

      def unconsolidated_messages
        @messages[@last_consolidated..]
      end

      def update_consolidated(index)
        @last_consolidated = index
        save_meta!
      end

      def get_history
        msgs = unconsolidated_messages || []
        # Align to start at a user turn
        user_idx = msgs.index { |m| m["role"] == "user" }
        user_idx ? msgs[user_idx..] : msgs
      end

      def clear!
        @messages = []
        @last_consolidated = 0
        File.delete(session_path) if File.exist?(session_path)
        File.delete(meta_path) if File.exist?(meta_path)
      end

      private

      def session_path
        FileUtils.mkdir_p(@dir)
        File.join(@dir, "#{safe_key}.jsonl")
      end

      def meta_path
        File.join(@dir, "#{safe_key}.meta.json")
      end

      def safe_key
        @key.gsub(/[^a-zA-Z0-9_\-]/, "_")
      end

      def load!
        if File.exist?(session_path)
          File.readlines(session_path).each do |line|
            @messages << JSON.parse(line.strip)
          rescue JSON::ParserError
            next
          end
        end

        if File.exist?(meta_path)
          meta = JSON.parse(File.read(meta_path))
          @last_consolidated = meta["last_consolidated"] || 0
        end
      rescue StandardError => e
        warn "Session load warning: #{e.message}"
      end

      def persist_entry(entry)
        File.open(session_path, "a") { |f| f.puts(JSON.generate(entry)) }
      end

      def save_meta!
        FileUtils.mkdir_p(@dir)
        File.write(meta_path, JSON.pretty_generate({ "last_consolidated" => @last_consolidated }))
      end
    end

    class Manager
      def initialize(sessions_dir:)
        @sessions_dir = sessions_dir
        @sessions = {}
      end

      def get(channel:, chat_id:)
        key = "#{channel}:#{chat_id}"
        @sessions[key] ||= Session.new(key: key, dir: @sessions_dir)
      end

      def clear(channel:, chat_id:)
        key = "#{channel}:#{chat_id}"
        @sessions[key]&.clear!
        @sessions.delete(key)
      end
    end
  end
end
