# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Hosts::Null do
  it 'declines every capability' do
    assert_empty Riffer::Rig::Hosts::Null.new.capabilities
  end

  it 'treats notify as a no-op' do
    assert_nil Riffer::Rig::Hosts::Null.new.notify('hi', level: :warn)
  end
end
