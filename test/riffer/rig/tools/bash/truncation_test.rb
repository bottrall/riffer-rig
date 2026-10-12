# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::Truncation do
  def setup
    @truncation = Object.new.extend(Riffer::Rig::Tools::Bash::Truncation)
    @max = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
  end

  it 'returns output within the limit unchanged' do
    assert_equal 'hello', @truncation.truncate('hello')
  end

  it 'cuts output over the limit down to it' do
    assert @truncation.truncate('a' * (@max + 1)).start_with?("#{'a' * @max}\n")
  end

  it 'marks output it cut' do
    assert @truncation.truncate('a' * (@max + 1)).end_with?("[output truncated to #{@max} bytes]")
  end

  it 'drops a character the limit falls inside' do
    assert @truncation.truncate("a#{'é' * (@max / 2)}").start_with?("a#{'é' * ((@max / 2) - 1)}\n")
  end
end
