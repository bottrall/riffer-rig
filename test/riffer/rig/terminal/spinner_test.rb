# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Spinner do
  it 'starts on its first frame' do
    assert_equal '⠋', Riffer::Rig::Terminal::Spinner.call(0)
  end

  it 'steps a frame each tick' do
    assert_equal '⠙', Riffer::Rig::Terminal::Spinner.call(1)
  end

  it 'wraps back to the first frame' do
    assert_equal '⠋', Riffer::Rig::Terminal::Spinner.call(Riffer::Rig::Terminal::Spinner::FRAMES.length)
  end
end
