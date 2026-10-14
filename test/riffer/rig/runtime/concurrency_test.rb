# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Concurrency do
  before do
    @concurrency = Riffer::Rig::Runtime::Concurrency.new
  end

  def refused?
    yield
    false
  rescue Riffer::Rig::Runtime::BusyError
    true
  end

  def held?
    refused? do
      @concurrency.claim
      @concurrency.release
    end
  end

  def refusal
    yield
    nil
  rescue Riffer::Rig::Runtime::BusyError, Riffer::Rig::Runtime::ClosedError => e
    e.message
  end

  def elsewhere
    Thread.new do
      Thread.current.report_on_exception = false
      yield
    end.value
  end

  def rebuild_refused_elsewhere?
    elsewhere { refused? { @concurrency.claim_rebuild } }
  end

  it 'starts free' do
    refute_predicate self, :held?
  end

  it 'starts open' do
    refute_predicate @concurrency, :closed?
  end

  describe '#claim' do
    it 'refuses a second claim from the thread that holds it' do
      @concurrency.claim

      assert_raises(Riffer::Rig::Runtime::BusyError) { @concurrency.claim }
    end

    it 'refuses a claim from another thread while one is held' do
      @concurrency.claim

      assert_raises(Riffer::Rig::Runtime::BusyError) { elsewhere { @concurrency.claim } }
    end

    it 'names the running prompt in the refusal' do
      @concurrency.claim

      assert_equal('a prompt is already running on this Runtime', refusal { @concurrency.claim })
    end

    it 'leaves the depth alone when it refuses' do
      @concurrency.claim
      begin
        @concurrency.claim
      rescue Riffer::Rig::Runtime::BusyError
        nil
      end
      @concurrency.release

      refute_predicate self, :held?
    end

    it 'refuses once closed' do
      @concurrency.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { @concurrency.claim }
    end

    it 'names the closed Runtime in the refusal' do
      @concurrency.close

      assert_equal('this Runtime is closed', refusal { @concurrency.claim })
    end

    it 'reports busy ahead of closed' do
      @concurrency.claim
      @concurrency.close

      assert_raises(Riffer::Rig::Runtime::BusyError) { @concurrency.claim }
    end

    it 'holds the Runtime' do
      @concurrency.claim

      assert_predicate self, :held?
    end
  end

  describe '#claim_rebuild' do
    it 'refuses another thread while one holds the Runtime' do
      @concurrency.claim

      assert_predicate self, :rebuild_refused_elsewhere?
    end

    it 'names the running prompt in the refusal' do
      @concurrency.claim

      assert_equal('a prompt is already running on this Runtime', elsewhere { refusal { @concurrency.claim_rebuild } })
    end

    it 'refuses once closed' do
      @concurrency.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { @concurrency.claim_rebuild }
    end

    it 'refuses a nested rebuild once closed' do
      @concurrency.claim
      @concurrency.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { @concurrency.claim_rebuild }
    end

    it 'reports busy ahead of closed to another thread' do
      @concurrency.claim
      @concurrency.close

      assert_predicate self, :rebuild_refused_elsewhere?
    end

    it 'holds a free Runtime' do
      @concurrency.claim_rebuild

      assert_predicate self, :held?
    end

    it 'nests under the thread that holds the Runtime' do
      @concurrency.claim

      refute(refused? { @concurrency.claim_rebuild })
    end

    it 'nests under a rebuild the same thread holds' do
      @concurrency.claim_rebuild

      refute(refused? { @concurrency.claim_rebuild })
    end
  end

  describe '#release' do
    it 'keeps the Runtime held while an outer claim remains' do
      @concurrency.claim
      @concurrency.claim_rebuild
      @concurrency.release

      assert_predicate self, :held?
    end

    it 'keeps the holding thread while an outer claim remains' do
      @concurrency.claim
      @concurrency.claim_rebuild
      @concurrency.release

      assert_predicate self, :rebuild_refused_elsewhere?
    end

    it 'frees the Runtime' do
      @concurrency.claim
      @concurrency.release

      refute_predicate self, :held?
    end

    it 'frees the Runtime once every nested claim is released' do
      @concurrency.claim
      @concurrency.claim_rebuild
      @concurrency.release
      @concurrency.release

      refute_predicate self, :held?
    end

    it 'forgets the holding thread' do
      @concurrency.claim
      @concurrency.release

      refute_predicate self, :rebuild_refused_elsewhere?
    end
  end

  describe '#busy?' do
    it 'is false while nothing holds the Runtime' do
      refute_predicate @concurrency, :busy?
    end

    it 'is true while a claim holds the Runtime' do
      @concurrency.claim

      assert_predicate @concurrency, :busy?
    end
  end

  describe '#close' do
    it 'closes' do
      @concurrency.close

      assert_predicate @concurrency, :closed?
    end

    it 'leaves a held claim to be released' do
      @concurrency.claim
      @concurrency.close
      @concurrency.release

      assert_raises(Riffer::Rig::Runtime::ClosedError) { @concurrency.claim }
    end
  end
end
