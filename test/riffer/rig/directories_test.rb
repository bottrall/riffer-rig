# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Directories do
  before do
    @tmp = Dir.mktmpdir
    @repo = File.join(@tmp, 'repo')
    @cwd = File.join(@repo, 'packages', 'app')
    FileUtils.mkdir_p(@cwd)
  end

  after do
    FileUtils.remove_entry(@tmp)
  end

  describe '.ancestors' do
    it 'lists the directory then each parent up to the filesystem root' do
      assert_equal ['/a/b', '/a', '/'], Riffer::Rig::Directories.ancestors('/a/b')
    end
  end

  describe '.up_to_repo_root' do
    it 'lists the cwd then each parent up to a repo root with a .git directory' do
      FileUtils.mkdir_p(File.join(@repo, '.git'))

      assert_equal [@cwd, File.join(@repo, 'packages'), @repo], Riffer::Rig::Directories.up_to_repo_root(@cwd)
    end

    it 'stops at a repo root with a .git file' do
      File.write(File.join(@repo, '.git'), 'gitdir: elsewhere')

      assert_equal [@cwd, File.join(@repo, 'packages'), @repo], Riffer::Rig::Directories.up_to_repo_root(@cwd)
    end

    it 'stops at the nearest .git' do
      FileUtils.mkdir_p([File.join(@repo, '.git'), File.join(@cwd, '.git')])

      assert_equal [@cwd], Riffer::Rig::Directories.up_to_repo_root(@cwd)
    end

    it 'lists only the cwd outside a repo' do
      assert_equal [@cwd], Riffer::Rig::Directories.up_to_repo_root(@cwd)
    end

    it 'expands a relative cwd' do
      FileUtils.mkdir_p(File.join(@repo, '.git'))

      assert_equal File.join(@repo, 'packages'), Dir.chdir(@cwd) { Riffer::Rig::Directories.up_to_repo_root('..').first }
    end
  end
end
