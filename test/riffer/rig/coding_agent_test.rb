# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::CodingAgent do
  it 'wraps present project agents file in the system prompt' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('AGENTS.md', 'ALWAYS_SQUAWK')
        agent = Riffer::Rig::CodingAgent.new

        assert_includes agent.instruction_message.content, '<project_instructions'
      end
    end
  end

  it 'includes project agents file content' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('AGENTS.md', 'ALWAYS_SQUAWK')
        agent = Riffer::Rig::CodingAgent.new

        assert_includes agent.instruction_message.content, 'ALWAYS_SQUAWK'
      end
    end
  end

  it 'skips a missing project agents file' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        agent = Riffer::Rig::CodingAgent.new

        refute_includes agent.instruction_message.content, File.join(dir, 'AGENTS.md')
      end
    end
  end

  it 'runs a turn against the mock provider' do
    response = mock_agent.generate('hello')

    assert_equal 'Mock response', response.content
  end

  it 'excludes skill activate tool when no skills are present' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        agent = isolated_agent(global_dir: dir, project_dir: dir)

        refute_includes agent.tools.map(&:name), 'skill_activate'
      end
    end
  end

  it 'includes skill activate tool when skills are present' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        skill_dir = File.join(dir, '.skills', 'test-skill')
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, 'SKILL.md'), <<~MD)
          ---
          name: test-skill
          description: A test skill.
          ---
          You are a test skill.
        MD

        # Point the backend at the .skills dir so it finds test-skill.
        agent = isolated_agent(global_dir: dir, project_dir: File.join(dir, '.skills'))

        assert_includes agent.tools.map(&:name), 'skill_activate'
      end
    end
  end

  it 'loads skills from project skills dir' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        skill_dir = File.join(dir, '.skills', 'refactor')
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, 'SKILL.md'), <<~MD)
          ---
          name: refactor
          description: Refactors code for clarity and maintainability.
          ---
          You are a refactoring assistant.
        MD

        agent = mock_agent
        agent.generate('hello')

        skills_msg = agent.session.messages.grep(Riffer::Messages::System)
                          .find { |m| m.content.include?('refactor') }

        refute_nil skills_msg
      end
    end
  end

  it 'uses xml adapter for claude models' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        skill_dir = File.join(dir, '.skills', 'refactor')
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, 'SKILL.md'), <<~MD)
          ---
          name: refactor
          description: Refactors code for clarity and maintainability.
          ---
          You are a refactoring assistant.
        MD

        agent = mock_agent(model: 'mock/claude-sonnet-4-6')
        agent.generate('hello')

        skills_msg = agent.session.messages.grep(Riffer::Messages::System)
                          .find { |m| m.content.include?('<available_skills>') }

        refute_nil skills_msg
      end
    end
  end

  private

  def mock_agent(model: 'mock/claude-test')
    config = Riffer::Rig::CodingAgent.config.dup
    config.model = model
    Riffer::Rig::CodingAgent.new(config: config)
  end

  # Builds an agent with a skills backend isolated to +global_dir+ and
  # +project_dir+, preventing the real ~/.riffer/skills from influencing
  # tool registration in tests.
  def isolated_agent(global_dir:, project_dir:)
    config = Riffer::Rig::CodingAgent.config.dup
    config.skills_config = Riffer::Skills::Config.new.tap do |sc|
      sc.backend(Riffer::Skills::FilesystemBackend.new(global_dir, project_dir))
    end
    Riffer::Rig::CodingAgent.new(config: config)
  end
end
