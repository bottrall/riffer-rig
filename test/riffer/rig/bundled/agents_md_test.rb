# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::AgentsMd' do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @original_home = Dir.home
    ENV['HOME'] = @home
    @project = File.join(@cwd, 'AGENTS.md')
    File.write(@project, 'PROJECT_RULES')
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def system_message(runtime)
    runtime.agent.provider.calls.last[:messages].first[:content]
  end

  it 'is named agents_md' do
    assert_equal 'agents_md', Riffer::Rig::Bundled::AgentsMd.name
  end

  it 'registers the agents_md prompt section' do
    registrar = Riffer::Rig::Registrar.new('agents_md')
    Riffer::Rig::Bundled::AgentsMd.run(registrar)

    assert_equal [:agents_md], registrar.prompts.keys
  end

  it "renders the Runtime cwd's AGENTS.md into the system message" do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig::Bundled::AgentsMd], cwd: @cwd)
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_includes system_message(runtime), "<project_instructions path=\"#{@project}\">\nPROJECT_RULES\n"
  end

  it 'picks up an edit between two turns with no rebuild' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig::Bundled::AgentsMd], cwd: @cwd)
    runtime.agent.provider.stub_response('One.')
    runtime.agent.provider.stub_response('Two.')
    runtime.ask('hello')
    File.write(@project, 'EDITED_RULES')
    runtime.ask('again')

    assert_includes system_message(runtime), 'EDITED_RULES'
  end

  it 'is replaced by a later extension registering :agents_md' do
    replacement = Riffer::Rig::Extension.new('mine') { |rig| rig.prompt(:agents_md) { 'MY_RULES' } }
    runtime = Riffer::Rig::Runtime.new(
      'mock/test',
      extensions: [Riffer::Rig::Bundled::AgentsMd, replacement],
      cwd: @cwd
    )
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    refute_includes system_message(runtime), 'PROJECT_RULES'
  end

  it 'reads no AGENTS.md into a Runtime it is not passed to' do
    runtime = Riffer::Rig::Runtime.new('mock/test', cwd: @cwd)
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    refute_includes system_message(runtime), 'PROJECT_RULES'
  end
end
