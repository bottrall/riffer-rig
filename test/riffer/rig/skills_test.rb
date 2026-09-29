# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Skills do
  before do
    @tmp = Dir.mktmpdir
    @repo = File.join(@tmp, 'repo')
    @cwd = File.join(@repo, 'packages', 'app')
    @home = File.join(@tmp, 'home')
    FileUtils.mkdir_p([@cwd, @home])
    @original_home = Dir.home
    ENV['HOME'] = @home
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.remove_entry(@tmp)
  end

  describe '.directories' do
    it 'lists .agents/skills up to the repo root closest first, then the home directory' do
      FileUtils.mkdir_p(File.join(@repo, '.git'))
      expected = [@cwd, File.join(@repo, 'packages'), @repo, @home].map { |dir| File.join(dir, '.agents', 'skills') }

      assert_equal expected, Riffer::Rig::Skills.directories(@cwd)
    end

    it 'lists only the cwd and the home directory outside a repo' do
      assert_equal [@cwd, @home].map { |dir| File.join(dir, '.agents', 'skills') }, Riffer::Rig::Skills.directories(@cwd)
    end
  end
end
