# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Format do
  it 'formats elapsed seconds under a minute' do
    assert_equal '41s', Riffer::Rig::Terminal::Format.elapsed(41.4)
  end

  it 'formats elapsed minutes' do
    assert_equal '2m05s', Riffer::Rig::Terminal::Format.elapsed(125.0)
  end

  it 'formats token counts under a thousand' do
    assert_equal '890', Riffer::Rig::Terminal::Format.tokens(890)
  end

  it 'formats token counts in k' do
    assert_equal '3.1k', Riffer::Rig::Terminal::Format.tokens(3123)
  end
end
