# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require_relative '../../../../rubocop/cop/rig/no_mocking'

describe RuboCop::Cop::Rig::NoMocking do
  def offenses(source)
    cop = RuboCop::Cop::Rig::NoMocking.new(RuboCop::Config.new)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'test/example_test.rb')
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  it 'flags Minitest::Mock' do
    assert_equal [1], offenses("host = Minitest::Mock.new\n").map(&:line)
  end

  it 'flags stub' do
    assert_equal [1], offenses("Time.stub(:now, 0) { run }\n").map(&:line)
  end

  it 'flags a singleton method defined on a rig constant' do
    assert_equal [1], offenses("Riffer::Rig::SDK.define_singleton_method(:bundler?) { false }\n").map(&:line)
  end

  it 'flags a singleton method defined on a top-level-qualified rig constant' do
    assert_equal [1], offenses("::Riffer::Rig::SDK.define_singleton_method(:bundler?) { false }\n").map(&:line)
  end

  it 'flags a singleton method defined on the rig namespace itself' do
    assert_equal [1], offenses("Riffer::Rig.define_singleton_method(:extension) { |*| nil }\n").map(&:line)
  end

  it 'flags a method defined on the singleton class of a rig constant' do
    assert_equal [1], offenses("Riffer::Rig::SDK.singleton_class.define_method(:bundler?) { false }\n").map(&:line)
  end

  it 'flags a method sent to the singleton class of a rig constant' do
    source = "Riffer::Rig::SDK.singleton_class.send(:define_method, :bundler?) { false }\n"

    assert_equal [1], offenses(source).map(&:line)
  end

  it 'flags a method defined on a rig class' do
    assert_equal [1], offenses("Riffer::Rig::Runtime.define_method(:close) { nil }\n").map(&:line)
  end

  it 'flags a method sent to a rig class' do
    assert_equal [1], offenses("Riffer::Rig::Runtime.send(:define_method, :close) { nil }\n").map(&:line)
  end

  it 'flags a method sent with __send__ to a rig class' do
    assert_equal [1], offenses("Riffer::Rig::Runtime.__send__(:define_method, :close) { nil }\n").map(&:line)
  end

  it 'allows a singleton method defined on a third-party constant' do
    assert_empty offenses("Gem.define_singleton_method(:find_files) { |_glob| [] }\n")
  end

  it 'flags a singleton method defined on a local built from a rig constant' do
    source = "host = Riffer::Rig::Hosts::Null.new\nhost.define_singleton_method(:notify) { |*| nil }\n"

    assert_equal [2], offenses(source).map(&:line)
  end

  it 'flags a singleton method given without a block on a local built from a rig constant' do
    source = "host = Riffer::Rig::Hosts::Null.new\nhost.define_singleton_method(:notify, handler)\n"

    assert_equal [2], offenses(source).map(&:line)
  end

  it 'allows a singleton method defined on a local built from another constant' do
    assert_empty offenses("io = StringIO.new\nio.define_singleton_method(:tty?) { true }\n")
  end

  it 'allows a singleton method defined on a local a helper returned' do
    assert_empty offenses("host = build_host\nhost.define_singleton_method(:notify) { |*| nil }\n")
  end

  it 'allows a singleton method defined on a local a rig constant built only in another scope' do
    source = <<~RUBY
      it('builds') { host = Riffer::Rig::Hosts::Null.new }
      it('patches') do
        host = FakeHost.new
        host.define_singleton_method(:notify) { |*| nil }
      end
    RUBY

    assert_empty offenses(source)
  end

  it 'allows a singleton method defined on an instance variable' do
    assert_empty offenses("@host.define_singleton_method(:notify) { |*| nil }\n")
  end

  it 'allows an injected fake' do
    assert_empty offenses("runtime = Runtime.new(host: FakeHost.new)\n")
  end
end
