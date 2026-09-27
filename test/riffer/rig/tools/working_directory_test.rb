# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::WorkingDirectory do
  it 'takes the cwd from the context' do
    assert_equal '/srv/app', Riffer::Rig::Tools::WorkingDirectory.of(Riffer::Agent::Context.new(cwd: '/srv/app'))
  end

  it 'falls back to the process directory without a context' do
    assert_equal Dir.pwd, Riffer::Rig::Tools::WorkingDirectory.of(nil)
  end

  it 'falls back to the process directory when the context has no cwd' do
    assert_equal Dir.pwd, Riffer::Rig::Tools::WorkingDirectory.of(Riffer::Agent::Context.new)
  end

  it 'expands a relative path against the cwd' do
    assert_equal '/srv/app/lib/a.rb',
                 Riffer::Rig::Tools::WorkingDirectory.expand('lib/a.rb', Riffer::Agent::Context.new(cwd: '/srv/app'))
  end

  it 'leaves an absolute path alone' do
    assert_equal '/etc/hosts',
                 Riffer::Rig::Tools::WorkingDirectory.expand('/etc/hosts', Riffer::Agent::Context.new(cwd: '/srv/app'))
  end
end
