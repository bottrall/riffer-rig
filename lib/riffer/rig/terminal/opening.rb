# frozen_string_literal: true

class Riffer::Rig::Terminal::Opening
  SKILL_COMMAND_PREFIX = 'skill:'

  # @rbs @animator: Riffer::Rig::Terminal::Animator
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @version: String
  # @rbs @sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs @jobs: Riffer::Rig::Terminal::JobCounter?
  # @rbs @repl: Riffer::Rig::Terminal::Repl?

  # @rbs animator: Riffer::Rig::Terminal::Animator
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs version: String
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs jobs: Riffer::Rig::Terminal::JobCounter?
  # @rbs repl: Riffer::Rig::Terminal::Repl?
  # @rbs return: void
  def initialize(animator:, theme:, version:, sessions:, jobs: nil, repl: nil)
    @animator = animator
    @theme = theme
    @version = version
    @sessions = sessions
    @jobs = jobs
    @repl = repl
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def call(runtime)
    @jobs&.watch(runtime)
    skills = runtime.commands.count { |command| command.name.start_with?(SKILL_COMMAND_PREFIX) }
    lines = Riffer::Rig::Terminal::Banner.lines(
      @theme,
      model: runtime.model,
      cwd: runtime.cwd,
      skills: skills.zero? ? 'none' : skills.to_s,
      version: @version,
      tally: runtime.tally
    )
    @animator.reveal([lines])
    @repl&.replay(@sessions.recorded(runtime.id), theme: @theme)
  end
end
