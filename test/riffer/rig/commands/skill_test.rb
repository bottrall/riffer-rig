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

  it 'names the command after the skill' do
    assert_equal 'skill:review', Riffer::Rig::Commands::Skill.command(@skill).name
  end

  it 'describes the command with the skill description' do
    assert_equal 'Review code.', Riffer::Rig::Commands::Skill.command(@skill).description
  end

  it 'belongs to core' do
    assert_equal 'core', Riffer::Rig::Commands::Skill.command(@skill).extension
  end

  it 'notifies when the Runtime no longer has skills' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    FileUtils.remove_entry(File.join(@dir, 'review'))
    runtime.model = 'mock/other'
    events = []
    runtime.run_command('skill:review') { |event| events << event }

    assert_equal [Riffer::Rig::Events::Notify.new('Skill review is no longer available', :error)], events
  end
end
