# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Hosts::Base do
  it 'leaves capabilities to the subclass' do
    assert_raises(NotImplementedError) { Riffer::Rig::Hosts::Base.new.capabilities }
  end

  it 'leaves ask to the subclass' do
    assert_raises(NotImplementedError) { Riffer::Rig::Hosts::Base.new.ask('hello') }
  end

  it 'leaves confirm to the subclass' do
    assert_raises(NotImplementedError) { Riffer::Rig::Hosts::Base.new.confirm('sure?') }
  end

  it 'leaves notify to the subclass' do
    assert_raises(NotImplementedError) { Riffer::Rig::Hosts::Base.new.notify('hi', level: :warn) }
  end

  it 'leaves progress to the subclass' do
    assert_raises(NotImplementedError) { Riffer::Rig::Hosts::Base.new.progress('working') { nil } }
  end

  it 'names the missing method' do
    error = assert_raises(NotImplementedError) { Class.new(Riffer::Rig::Hosts::Base).new.confirm }

    assert_match(/must implement confirm/, error.message)
  end
end
