# frozen_string_literal: true

require "thor"
require "async"
require_relative "../nanobotrb"

module Nanobotrb
  class CLI < Thor
    desc "agent", "Interactive CLI chat (or single-shot with -m)"
    option :message, aliases: "-m", type: :string, desc: "Single message to process"
    option :model, type: :string, desc: "Model to use"
    def agent
      config = Config.new
      config.data["model"] = options[:model] if options[:model]

      bus = Bus::MessageBus.new
      agent_loop = Agent::Loop.new(config: config, bus: bus)

      if options[:message]
        # Single-shot mode
        Async do
          result = agent_loop.process_direct(options[:message])
          # Consume the outbound message
          outbound = bus.consume_outbound
          puts outbound.content
        end
      else
        # Interactive mode
        interactive_mode(agent_loop, bus)
      end
    end

    desc "gateway", "Start multi-channel server"
    def gateway
      config = Config.new

      Async do |task|
        bus = Bus::MessageBus.new
        agent_loop = Agent::Loop.new(config: config, bus: bus)
        channel_manager = Channels::Manager.new(bus: bus, config: config)

        # Register enabled channels
        if config.channel_config("telegram")["enabled"]
          telegram = Channels::Telegram.new(bus: bus, config: config)
          channel_manager.register(telegram)
        end

        puts "Starting nanobot gateway..."

        # Run agent loop and channels concurrently
        task.async { agent_loop.run }
        task.async { channel_manager.start_all }
      end
    end

    desc "onboard", "First-time setup"
    def onboard
      config = Config.onboard!
      puts "Created config at: #{config.config_dir}"
      puts "Workspace at: #{config.workspace_dir}"
      puts ""
      puts "Next steps:"
      puts "  1. Add your API key to #{File.join(config.config_dir, "config.json")}"
      puts "  2. Run: nanobotrb agent -m 'Hello!'"
    end

    desc "status", "Show config and status"
    def status
      config = Config.new
      puts "Config dir:  #{config.config_dir}"
      puts "Workspace:   #{config.workspace_dir}"
      puts "Model:       #{config.model}"
      puts "Temperature: #{config.temperature}"
      puts ""

      %w[openai anthropic gemini deepseek].each do |provider|
        key = config.dig("providers", provider, "api_key") || ENV["#{provider.upcase}_API_KEY"]
        status = key ? "configured" : "not set"
        puts "#{provider.ljust(12)} #{status}"
      end

      puts ""
      telegram_cfg = config.channel_config("telegram")
      telegram_status = telegram_cfg["enabled"] ? "enabled" : "disabled"
      puts "Telegram:    #{telegram_status}"
    end

    desc "version", "Show version"
    def version
      puts "nanobotrb v#{Nanobotrb::VERSION}"
    end

    private

    def interactive_mode(agent_loop, bus)
      puts "nanobot interactive mode (type /help for commands, Ctrl+C to exit)"
      puts ""

      Async do |task|
        # Background task to print responses
        task.async do
          loop do
            outbound = bus.consume_outbound
            puts "\nnanobot> #{outbound.content}\n\n"
            print "you> "
          end
        end

        # Read input
        loop do
          print "you> "
          input = $stdin.gets&.strip
          break if input.nil? || input == "/quit"

          next if input.empty?

          agent_loop.process_direct(input)
        end
      end

      puts "\nGoodbye!"
    end
  end
end
