# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Env do
  let(:pair) do
    Riffer::Rig::ProviderSetup::Field.new(
      name: :api_key, env: %w[ACME_API_KEY ACME_TOKEN], secret: true, required: true
    )
  end

  describe '#[]' do
    it 'returns the value of a set variable' do
      assert_equal 'sk-acme', Riffer::Rig::Env.new('ACME_API_KEY' => 'sk-acme')['ACME_API_KEY']
    end

    it 'treats a blank value as absent' do
      assert_nil Riffer::Rig::Env.new('ACME_API_KEY' => ' ')['ACME_API_KEY']
    end

    it 'is nil for an unset variable' do
      assert_nil Riffer::Rig::Env.new({})['ACME_API_KEY']
    end
  end

  describe '#value_for' do
    it 'returns the first of the field vars that is set' do
      env = Riffer::Rig::Env.new('ACME_API_KEY' => 'from-key', 'ACME_TOKEN' => 'from-token')

      assert_equal 'from-key', env.value_for(pair)
    end

    it 'skips a blank var for the next one' do
      env = Riffer::Rig::Env.new('ACME_API_KEY' => '', 'ACME_TOKEN' => 'from-token')

      assert_equal 'from-token', env.value_for(pair)
    end

    it 'is nil when none of the field vars are set' do
      assert_nil Riffer::Rig::Env.new({}).value_for(pair)
    end
  end

  describe '#no_color' do
    it 'is true when NO_COLOR is set' do
      assert Riffer::Rig::Env.new('NO_COLOR' => '1').no_color
    end

    it 'is true when NO_COLOR is set to an empty value' do
      assert Riffer::Rig::Env.new('NO_COLOR' => '').no_color
    end

    it 'is false when NO_COLOR is unset' do
      refute Riffer::Rig::Env.new({}).no_color
    end
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Env.new({}), :frozen?
  end

  it 'is the only place rig reads the process environment' do
    offenders = files_reading_env

    assert_empty offenders, "#{offenders.join(', ')} read ENV directly — take a Riffer::Rig::Env instead"
  end

  private

  def files_reading_env
    root = File.expand_path('../../..', __dir__)

    Dir.glob(File.join(root, '{lib,exe}', '**', '*'))
       .select { |path| File.file?(path) && File.read(path).match?(/\bENV\b/) }
       .map { |path| path.delete_prefix("#{root}/") }
       .reject { |path| path == 'lib/riffer/rig/env.rb' }
  end
end
