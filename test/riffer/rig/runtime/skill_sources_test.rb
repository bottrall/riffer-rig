# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::SkillSources do
  before do
    @first = Dir.mktmpdir
    @second = Dir.mktmpdir
    write_skill(@first, 'a', 'first a')
    write_skill(@second, 'a', 'second a')
    write_skill(@second, 'b', 'second b')
    @sources = Riffer::Rig::Runtime::SkillSources.new(
      [Riffer::Skills::FilesystemBackend.new(@first), Riffer::Skills::FilesystemBackend.new(@second)]
    )
  end

  after do
    FileUtils.remove_entry(@first)
    FileUtils.remove_entry(@second)
  end

  def write_skill(root, name, body)
    FileUtils.mkdir_p(File.join(root, name))
    File.write(File.join(root, name, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\n#{body}\n")
  end

  it 'lists the skills of every source, once per name' do
    assert_equal %w[a b], @sources.list_skills.map(&:name)
  end

  it 'reads a skill from the earliest source that has it' do
    assert_equal "first a\n", @sources.read_skill('a')
  end

  it 'reads a skill only a later source has' do
    assert_equal "second b\n", @sources.read_skill('b')
  end

  it 'raises for a skill no source has' do
    assert_raises(Riffer::ArgumentError) { @sources.read_skill('gone') }
  end
end
