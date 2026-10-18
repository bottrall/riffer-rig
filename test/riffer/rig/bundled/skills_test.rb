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

  def write_skill(root, name)
    FileUtils.mkdir_p(File.join(root, name))
    File.write(File.join(root, name, 'SKILL.md'), <<~MD)
      ---
      name: #{name}
      description: Skill #{name}.
      ---
      Follow skill #{name}.
    MD
  end

  def runtime
    Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig::Bundled::Skills], cwd: @cwd)
  end

  it 'is named skills' do
    assert_equal 'skills', Riffer::Rig::Bundled::Skills.name
  end

  it 'registers one skills source' do
    registrar = Riffer::Rig::Registrar.new('skills')
    Riffer::Rig::Bundled::Skills.run(registrar)

    assert_equal 1, registrar.skill_sources.length
  end

  it 'lists one command per skill in the project directory' do
    assert_equal %w[auth model reasoning cost skill:a skill:b], runtime.commands.map(&:name)
  end

  it 'lists a command for a skill in the home directory' do
    write_skill(File.join(@home, '.agents', 'skills'), 'c')

    assert_includes runtime.commands.map(&:name), 'skill:c'
  end

  it 'registers the skills prompt section' do
    registrar = Riffer::Rig::Registrar.new('skills')
    Riffer::Rig::Bundled::Skills.run(registrar)

    assert_equal [:skills], registrar.prompts.keys
  end

  it 'leaves the skills section empty' do
    registrar = Riffer::Rig::Registrar.new('skills')
    Riffer::Rig::Bundled::Skills.run(registrar)

    assert_nil registrar.prompts.fetch(:skills).call(runtime)
  end
end
