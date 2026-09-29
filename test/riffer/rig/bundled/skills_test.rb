# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Skills' do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @original_home = Dir.home
    ENV['HOME'] = @home
    write_skill(File.join(@cwd, '.agents', 'skills'), 'a')
    write_skill(File.join(@cwd, '.agents', 'skills'), 'b')
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def write_skill(root, name, description = "Skill #{name}.")
    FileUtils.mkdir_p(File.join(root, name))
    File.write(File.join(root, name, 'SKILL.md'), <<~MD)
      ---
      name: #{name}
      description: #{description}
      ---
      Follow skill #{name}.
    MD
  end

  def runtime(extensions = [Riffer::Rig::Bundled::Skills], cwd: @cwd)
    Riffer::Rig::Runtime.new('mock/test', extensions: extensions, cwd: cwd)
  end

  def skill_description(runtime, name)
    runtime.commands.find { |command| command.name == "skill:#{name}" }.description
  end

  def in_repo
    outer = Dir.mktmpdir
    repo = File.join(outer, 'repo')
    nested = File.join(repo, 'pkg', 'app')
    FileUtils.mkdir_p([nested, File.join(repo, '.git')])
    yield outer, repo, nested
  ensure
    FileUtils.remove_entry(outer)
  end

  def run_skill(runtime, name, args = '')
    runtime.agent.provider.stub_response('On it.')
    events = []
    runtime.run_command(name, args) { |event| events << event }
    events
  end

  def last_user_turn(runtime)
    runtime.agent.provider.calls.last[:messages].last[:content]
  end

  it 'is named skills' do
    assert_equal 'skills', Riffer::Rig::Bundled::Skills.name
  end

  it 'registers one skills source' do
    registrar = Riffer::Rig::Registrar.new('skills')
    Riffer::Rig::Bundled::Skills.run(registrar)

    assert_equal 1, registrar.skill_sources.length
  end

  it 'registers the skills prompt section' do
    registrar = Riffer::Rig::Registrar.new('skills')
    Riffer::Rig::Bundled::Skills.run(registrar)

    assert_equal [:skills], registrar.prompts.keys
  end

  it 'lists one command per skill in the project directory' do
    assert_equal %w[model skill:a skill:b], runtime.commands.map(&:name)
  end

  it 'lists a command for a skill in the home directory' do
    write_skill(File.join(@home, '.agents', 'skills'), 'c')

    assert_includes runtime.commands.map(&:name), 'skill:c'
  end

  it 'lists a command for a skill in the repo root from a nested cwd' do
    in_repo do |_outer, repo, nested|
      write_skill(File.join(repo, '.agents', 'skills'), 'c')

      assert_includes runtime(cwd: nested).commands.map(&:name), 'skill:c'
    end
  end

  it 'prefers the directory closest to the cwd for a name' do
    in_repo do |_outer, repo, nested|
      write_skill(File.join(repo, '.agents', 'skills'), 'c', 'Root.')
      write_skill(File.join(repo, 'pkg', '.agents', 'skills'), 'c', 'Package.')

      assert_equal 'Package.', skill_description(runtime(cwd: nested), 'c')
    end
  end

  it 'prefers a project skill over a home skill of the same name' do
    write_skill(File.join(@home, '.agents', 'skills'), 'a', 'Home.')

    assert_equal 'Skill a.', skill_description(runtime, 'a')
  end

  it 'ignores skills above the repo root' do
    in_repo do |outer, _repo, nested|
      write_skill(File.join(outer, '.agents', 'skills'), 'c')

      refute_includes runtime(cwd: nested).commands.map(&:name), 'skill:c'
    end
  end

  it 'reads only the cwd outside a repo' do
    sub = File.join(@cwd, 'sub')
    FileUtils.mkdir_p(sub)

    assert_equal %w[model], runtime(cwd: sub).commands.map(&:name)
  end

  it 'describes a skill command with the skill description' do
    assert_equal 'Skill a.', skill_description(runtime, 'a')
  end

  it 'lists no skill commands without skills' do
    FileUtils.remove_entry(File.join(@cwd, '.agents', 'skills'))

    assert_equal %w[model], runtime.commands.map(&:name)
  end

  it 'sends the wrapped body and the args as a user turn' do
    rig = runtime
    run_skill(rig, 'skill:a', 'on foo.rb')

    assert_equal "<skill_content name=\"a\">\nFollow skill a.\n\n</skill_content>\n\non foo.rb", last_user_turn(rig)
  end

  it 'sends the wrapped body alone without args' do
    rig = runtime
    run_skill(rig, 'skill:a')

    assert_equal "<skill_content name=\"a\">\nFollow skill a.\n\n</skill_content>", last_user_turn(rig)
  end

  it 'emits skill_activated' do
    events = run_skill(runtime, 'skill:a')

    assert_equal [Riffer::Rig::Events::SkillActivated.new('a')], events.grep(Riffer::Rig::Events::SkillActivated)
  end

  it 'leaves the skill unactivated in the model catalog' do
    rig = runtime
    run_skill(rig, 'skill:a')

    refute rig.agent.context.skills.activated?('a')
  end

  it 'leaves the skills section empty' do
    registrar = Riffer::Rig::Registrar.new('skills')
    Riffer::Rig::Bundled::Skills.run(registrar)

    assert_nil registrar.prompts.fetch(:skills).call(runtime)
  end

  it 'is replaced by a later extension registering :skills' do
    replacement = Riffer::Rig::Extension.new('mine') { |rig| rig.prompt(:skills) { 'MY_SKILL_NOTES' } }
    rig = runtime([Riffer::Rig::Bundled::Skills, replacement])
    rig.agent.provider.stub_response('Hi.')
    rig.ask('hello')

    assert_includes rig.agent.provider.calls.last[:messages].first[:content], 'MY_SKILL_NOTES'
  end

  it 'reads no skills into a Runtime it is not passed to' do
    assert_nil runtime([]).agent.context.skills
  end
end
