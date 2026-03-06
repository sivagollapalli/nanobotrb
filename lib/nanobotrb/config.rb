# frozen_string_literal: true

require "json"
require "fileutils"

module Nanobotrb
  class Config
    DEFAULT_DIR = File.join(Dir.home, ".nanobotrb")
    CONFIG_FILE = "config.json"

    DEFAULTS = {
      "model" => "gpt-4.1-nano",
      "provider" => nil,
      "temperature" => 0.7,
      "max_tokens" => 4096,
      "memory_window" => 100,
      "max_iterations" => 40,
      "channels" => {},
      "providers" => {},
      "tools" => { "exec_timeout" => 30, "restrict_to_workspace" => true }
    }.freeze

    attr_reader :data, :config_dir, :workspace_dir

    def initialize(config_dir: DEFAULT_DIR)
      @config_dir = config_dir
      @workspace_dir = File.join(config_dir, "workspace")
      @data = DEFAULTS.dup
      load_config
    end

    def [](key)
      @data[key.to_s]
    end

    def dig(*keys)
      @data.dig(*keys.map(&:to_s))
    end

    def model = @data["model"]
    def temperature = @data["temperature"]
    def max_tokens = @data["max_tokens"]
    def memory_window = @data["memory_window"]
    def max_iterations = @data["max_iterations"]

    def channel_config(name)
      @data.dig("channels", name.to_s) || {}
    end

    def provider_config(name)
      @data.dig("providers", name.to_s) || {}
    end

    def sessions_dir
      File.join(@workspace_dir, "sessions")
    end

    def memory_dir
      File.join(@workspace_dir, "memory")
    end

    def save!
      ensure_dirs!
      File.write(config_path, JSON.pretty_generate(@data))
    end

    def self.onboard!
      config = new
      config.save!
      config
    end

    private

    def config_path
      File.join(@config_dir, CONFIG_FILE)
    end

    def load_config
      return unless File.exist?(config_path)

      file_data = JSON.parse(File.read(config_path))
      @data = DEFAULTS.merge(file_data)
    rescue JSON::ParserError => e
      warn "Warning: Could not parse config file: #{e.message}"
    end

    def ensure_dirs!
      [config_dir, workspace_dir, sessions_dir, memory_dir].each do |dir|
        FileUtils.mkdir_p(dir)
      end
    end
  end
end
