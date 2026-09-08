# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::HostTest < Minitest::Test
  def test_capabilities_is_empty
    assert_empty Riffer::Rig::Host.new.capabilities
  end

  def test_ask_returns_nil
    assert_nil Riffer::Rig::Host.new.ask('hello')
  end

  def test_confirm_returns_false
    refute Riffer::Rig::Host.new.confirm('sure?')
  end

  def test_notify_is_a_no_op
    assert_nil Riffer::Rig::Host.new.notify('hi', level: :warn)
  end

  def test_progress_yields
    yielded = false
    Riffer::Rig::Host.new.progress('working') { yielded = true }

    assert yielded
  end
end
