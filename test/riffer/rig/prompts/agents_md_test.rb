# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Prompts::AgentsMd do
  before do
    @tmp = Dir.mktmpdir
    @original_home = Dir.home
    ENV['HOME'] = File.join(@tmp, 'home')
    @repo = File.join(@tmp, 'repo')
    @cwd = File.join(@repo, 'packages', 'app')
    FileUtils.mkdir_p([File.join(Dir.home, '.riffer'), @cwd])
    @global = File.join(Dir.home, '.riffer', 'AGENTS.md')
    @outer = File.join(@repo, 'AGENTS.md')
    @inner = File.join(@cwd, 'AGENTS.md')
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.remove_entry(@tmp)
  end

  def write_all
    File.write(@global, 'GLOBAL_RULES')
    File.write(@outer, 'REPO_RULES')
    File.write(@inner, 'APP_RULES')
  end

  # The walk reaches the real filesystem root, so a stray AGENTS.md above the
  # tmpdir would otherwise leak into these assertions.
  def own_paths(cwd)
    Riffer::Rig::Prompts::AgentsMd.paths(cwd).select { |path| path.start_with?(@tmp) }
  end

  it 'lists the global file, then every ancestor file from the outermost down to the cwd' do
    write_all

    assert_equal [@global, @outer, @inner], own_paths(@cwd)
  end

  it 'lists only the files that exist' do
    File.write(@outer, 'REPO_RULES')

    assert_equal [@outer], own_paths(@cwd)
  end

  it 'resolves a relative cwd against the process working directory' do
    File.write(@inner, 'APP_RULES')

    assert_equal [@inner], Dir.chdir(@repo) { own_paths('packages/app') }
  end

  it 'lists the global file once when the cwd is its directory' do
    File.write(@global, 'GLOBAL_RULES')

    assert_equal [@global], own_paths(File.dirname(@global))
  end

  it 'renders one block per file in order, each with its absolute path' do
    write_all

    blocks = [[@global, 'GLOBAL_RULES'], [@outer, 'REPO_RULES'], [@inner, 'APP_RULES']].map do |path, rules|
      "<project_instructions path=\"#{path}\">\n#{rules}\n</project_instructions>"
    end

    assert Riffer::Rig::Prompts::AgentsMd.section(@cwd).end_with?("\n\n#{blocks.join("\n\n")}")
  end

  it 'leads the section with the framing sentence' do
    write_all

    assert Riffer::Rig::Prompts::AgentsMd.section(@cwd).start_with?("#{Riffer::Rig::Prompts::AgentsMd::FRAMING}\n\n")
  end

  it 'renders nothing when no file exists' do
    skip 'an AGENTS.md above the tmpdir' unless Riffer::Rig::Prompts::AgentsMd.paths(@cwd).empty?

    assert_nil Riffer::Rig::Prompts::AgentsMd.section(@cwd)
  end
end
