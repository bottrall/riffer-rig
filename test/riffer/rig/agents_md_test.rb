# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::AgentsMd do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @original_home = Dir.home
    ENV['HOME'] = @home
    @global = File.join(@home, '.riffer', 'AGENTS.md')
    @project = File.join(@cwd, 'AGENTS.md')
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def write_both
    FileUtils.mkdir_p(File.dirname(@global))
    File.write(@global, 'GLOBAL_RULES')
    File.write(@project, 'PROJECT_RULES')
  end

  it 'lists the global file before the project file' do
    write_both

    assert_equal [@global, @project], Riffer::Rig::AgentsMd.paths(@cwd)
  end

  it 'lists only the files that exist' do
    File.write(@project, 'PROJECT_RULES')

    assert_equal [@project], Riffer::Rig::AgentsMd.paths(@cwd)
  end

  it 'renders the global block before the project block, each with its absolute path' do
    write_both

    blocks = [
      "<project_instructions path=\"#{@global}\">\nGLOBAL_RULES\n</project_instructions>",
      "<project_instructions path=\"#{@project}\">\nPROJECT_RULES\n</project_instructions>"
    ].join("\n\n")

    assert Riffer::Rig::AgentsMd.section(@cwd).end_with?("\n\n#{blocks}")
  end

  it 'leads the section with the framing sentence' do
    write_both

    assert Riffer::Rig::AgentsMd.section(@cwd).start_with?("#{Riffer::Rig::AgentsMd::FRAMING}\n\n")
  end

  it 'renders nothing when neither file exists' do
    assert_nil Riffer::Rig::AgentsMd.section(@cwd)
  end
end
