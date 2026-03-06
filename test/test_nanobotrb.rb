# frozen_string_literal: true

require "test_helper"

class TestNanobotrb < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Nanobotrb::VERSION
  end
end

class TestConfig < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("nanobotrb_test")
    @config = Nanobotrb::Config.new(config_dir: @tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_default_model
    assert_equal "gpt-4.1-nano", @config.model
  end

  def test_default_temperature
    assert_equal 0.7, @config.temperature
  end

  def test_save_and_reload
    @config.save!
    reloaded = Nanobotrb::Config.new(config_dir: @tmpdir)
    assert_equal @config.model, reloaded.model
  end

  def test_sessions_dir
    assert_match(/sessions$/, @config.sessions_dir)
  end
end

class TestMessageBus < Minitest::Test
  def test_publish_and_consume
    require "async"

    bus = Nanobotrb::Bus::MessageBus.new
    msg = Nanobotrb::Bus::InboundMessage.new(
      channel: "test", sender_id: "1", chat_id: "1", content: "hello"
    )

    result = nil
    Async do |task|
      task.async { bus.publish_inbound(msg) }
      task.async { result = bus.consume_inbound }
    end

    assert_equal "hello", result.content
    assert_equal "test", result.channel
  end
end

class TestSession < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("nanobotrb_sessions")
    @manager = Nanobotrb::Session::Manager.new(sessions_dir: @tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_get_session
    session = @manager.get(channel: "test", chat_id: "123")
    assert_equal "test:123", session.key
  end

  def test_append_and_history
    session = @manager.get(channel: "test", chat_id: "123")
    session.append(role: "user", content: "hello")
    session.append(role: "assistant", content: "hi there")

    history = session.get_history
    assert_equal 2, history.length
    assert_equal "user", history[0]["role"]
  end

  def test_clear_session
    session = @manager.get(channel: "test", chat_id: "456")
    session.append(role: "user", content: "test")
    session.clear!
    assert_empty session.messages
  end
end

class TestToolRegistry < Minitest::Test
  def setup
    @registry = Nanobotrb::Agent::Tools::Registry.new
  end

  def test_register_and_execute
    tool = Nanobotrb::Agent::Tools::ReadFile.new
    @registry.register(tool)

    assert_includes @registry.tool_names, "read_file"
    assert_equal 1, @registry.definitions.length
  end
end

class TestMemory < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("nanobotrb_memory")
    @memory = Nanobotrb::Agent::Memory.new(memory_dir: @tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_save_and_read_memory
    @memory.save_memory("User prefers Ruby")
    assert_equal "User prefers Ruby", @memory.long_term
  end

  def test_append_history
    @memory.append_history("Had a conversation about Ruby")
    assert_match(/conversation about Ruby/, @memory.history)
  end
end

class TestMessages < Minitest::Test
  def test_inbound_message_defaults
    msg = Nanobotrb::Bus::InboundMessage.new(
      channel: "telegram", sender_id: "1", chat_id: "2", content: "hi"
    )
    assert_nil msg.media
    assert_equal({}, msg.metadata)
  end

  def test_outbound_message_defaults
    msg = Nanobotrb::Bus::OutboundMessage.new(
      channel: "telegram", chat_id: "2", content: "hello"
    )
    assert_nil msg.reply_to
    assert_nil msg.media
  end
end
