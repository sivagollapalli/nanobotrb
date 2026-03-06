# frozen_string_literal: true

require_relative "nanobotrb/version"
require_relative "nanobotrb/config"
require_relative "nanobotrb/bus/message_bus"
require_relative "nanobotrb/bus/messages"
require_relative "nanobotrb/session/manager"
require_relative "nanobotrb/agent/context_builder"
require_relative "nanobotrb/agent/memory"
require_relative "nanobotrb/agent/tools/registry"
require_relative "nanobotrb/agent/tools/base"
require_relative "nanobotrb/agent/tools/read_file"
require_relative "nanobotrb/agent/tools/write_file"
require_relative "nanobotrb/agent/tools/exec"
require_relative "nanobotrb/agent/tools/web_search"
require_relative "nanobotrb/agent/loop"
require_relative "nanobotrb/channels/base"
require_relative "nanobotrb/channels/manager"
require_relative "nanobotrb/channels/telegram"
require_relative "nanobotrb/providers/base"
require_relative "nanobotrb/providers/ruby_llm_provider"

module Nanobotrb
  class Error < StandardError; end
end
