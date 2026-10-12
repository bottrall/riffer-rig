# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Commands::Skill do
  before do
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, 'review'))
    File.write(File.join(@dir, 'review', 'SKILL.md'), "---\nname: review\ndescription: Review code.\n---\nReview it.\n")
    @skill = Riffer::Skills::Frontmatter.new(name: 'review', description: 'Review code.')
    @extension = Riffer::Rig::Extension.new('local') { |rig| rig.skills { |_runtime| Riffer::Skills::FilesystemBackend.new(@dir) } }
  end

  after do
    FileUtils.remove_entry(@dir)
  end

  def run_skill(args = '')
    @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    @prompts = []
    @events = []
    ctx = Riffer::Rig::Command::Context.new(
      'skill:review',
      args,
      runtime: @runtime,
      host: Riffer::Rig::Hosts::Null.new,
      settings: {},
      emit: ->(event) { @events << event },
      turn: ->(text) { @prompts << text }
    )
    Riffer::Rig::Commands::Skill.run(ctx, @skill)
  end

  it 'names the command after the skill' do
    assert_equal 'skill:review', Riffer::Rig::Commands::Skill.command(@skill).name
  end

  it 'describes the command with the skill description' do
    assert_equal 'Review code.', Riffer::Rig::Commands::Skill.command(@skill).description
  end

  it 'notifies when the Runtime no longer has skills' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    FileUtils.remove_entry(File.join(@dir, 'review'))
    runtime.model = 'mock/other'
    events = []
    runtime.run_command('skill:review') { |event| events << event }

    assert_equal [Riffer::Rig::Events::Notify.new('Skill review is no longer available', :error)], events
  end

  it 'leaves the skill out of the model activations' do
    run_skill

    refute @runtime.agent.context.skills.activated?('review')
  end

  it 'emits SkillActivated for the skill' do
    run_skill

    assert_equal [Riffer::Rig::Events::SkillActivated.new('review')], @events
  end

  it 'prompts with the skill body rendered as an activation' do
    run_skill

    assert_equal "<skill_content name=\"review\">\nReview it.\n\n</skill_content>", @prompts.first
  end

  it 'appends the stripped args after the skill content, separated by a blank line' do
    run_skill("  focus on tests  \n")

    assert @prompts.first.end_with?("\n\nfocus on tests")
  end

  it 'sends the skill content alone when no args are given' do
    run_skill

    refute @prompts.first.end_with?("\n")
  end
end
