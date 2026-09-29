# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::SkillDirectories' do
  before do
    @home = Dir.mktmpdir
    @original_home = Dir.home
    ENV['HOME'] = @home
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.remove_entry(@home)
  end

  def in_repo
    outer = Dir.mktmpdir
    repo = File.join(outer, 'repo')
    nested = File.join(repo, 'pkg', 'app')
    FileUtils.mkdir_p([nested, File.join(repo, '.git')])
    yield repo, nested
  ensure
    FileUtils.remove_entry(outer)
  end

  it 'lists the project directories closest first, then the home directory' do
    in_repo do |repo, nested|
      expected = [
        File.join(nested, '.agents', 'skills'),
        File.join(repo, 'pkg', '.agents', 'skills'),
        File.join(repo, '.agents', 'skills'),
        File.join(@home, '.agents', 'skills')
      ]

      assert_equal expected, Riffer::Rig::SkillDirectories.for(nested)
    end
  end

  it 'lists only the cwd and the home directory outside a repo' do
    cwd = Dir.mktmpdir
    expected = [File.join(cwd, '.agents', 'skills'), File.join(@home, '.agents', 'skills')]

    assert_equal expected, Riffer::Rig::SkillDirectories.for(cwd)
  ensure
    FileUtils.remove_entry(cwd)
  end
end
