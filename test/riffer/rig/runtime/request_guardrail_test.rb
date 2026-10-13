# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::RequestGuardrail do
  def hooks_returning(verdict)
    Class.new do
      def initialize(verdict)
        @verdict = verdict
      end

      def before_request(_messages)
        @verdict
      end
    end.new(verdict)
  end

  def guardrail_with(verdict)
    Riffer::Rig::Runtime::RequestGuardrail.new(hooks: hooks_returning(verdict))
  end

  describe '#process_input' do
    it 'holds an abort off while the hooks run' do
      abort = Riffer::Rig::Runtime::Abort.new
      messages = [Riffer::Messages::User.new('hi')]
      aborting = Class.new do
        define_method(:before_request) do |given|
          abort.fire
          sleep(0)
          given
        end
      end.new
      guardrail = Riffer::Rig::Runtime::RequestGuardrail.new(hooks: aborting)
      result = abort.window { guardrail.process_input(messages, context: nil) }

      assert_predicate result, :pass?
    end

    it 'blocks when the hooks block the request' do
      guardrail = guardrail_with(Riffer::Rig::Runtime::Blocked.new('no force pushes'))
      result = guardrail.process_input([Riffer::Messages::User.new('hi')], context: nil)

      assert_predicate result, :block?
    end

    it 'carries the blocking reason as the result data' do
      guardrail = guardrail_with(Riffer::Rig::Runtime::Blocked.new('no force pushes'))
      result = guardrail.process_input([Riffer::Messages::User.new('hi')], context: nil)

      assert_equal 'no force pushes', result.data
    end

    it 'passes when the hooks return the same messages' do
      messages = [Riffer::Messages::User.new('hi')]
      result = guardrail_with(messages).process_input(messages, context: nil)

      assert_predicate result, :pass?
    end

    it 'passes the same messages object through' do
      messages = [Riffer::Messages::User.new('hi')]
      result = guardrail_with(messages).process_input(messages, context: nil)

      assert_same messages, result.data
    end

    it 'transforms when the hooks return different messages' do
      messages = [Riffer::Messages::User.new('hi')]
      rewritten = [Riffer::Messages::User.new('hi, redacted')]
      result = guardrail_with(rewritten).process_input(messages, context: nil)

      assert_predicate result, :transform?
    end

    it 'transforms to data equal to the returned messages' do
      messages = [Riffer::Messages::User.new('hi')]
      rewritten = [Riffer::Messages::User.new('hi, redacted')]
      result = guardrail_with(rewritten).process_input(messages, context: nil)

      assert_equal rewritten, result.data
    end

    it 'transforms to a copy rather than the returned object' do
      messages = [Riffer::Messages::User.new('hi')]
      rewritten = [Riffer::Messages::User.new('hi, redacted')]
      result = guardrail_with(rewritten).process_input(messages, context: nil)

      refute_same rewritten, result.data
    end
  end
end
