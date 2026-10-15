# frozen_string_literal: true

class Riffer::Rig::Terminal::Opening
  SKILL_COMMAND_PREFIX = 'skill:'

  # @rbs @io: Riffer::Rig::Terminal::_Output
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @version: String
  # @rbs @sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs @jobs: Riffer::Rig::Terminal::JobCounter?
  # @rbs @repl: Riffer::Rig::Terminal::Repl?

  # @rbs io: Riffer::Rig::Terminal::_Output
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs version: String
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs jobs: Riffer::Rig::Terminal::JobCounter?
  # @rbs repl: Riffer::Rig::Terminal::Repl?
  # @rbs return: void
  def initialize(io:, theme:, version:, sessions:, jobs: nil, repl: nil)
    @io = io
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
    @repl&.watch(runtime)
    skills = runtime.commands.count { |command| command.name.start_with?(SKILL_COMMAND_PREFIX) }
    Riffer::Rig::Terminal::Banner.lines(
      @theme,
      model: runtime.model,
      cwd: runtime.cwd,
      skills: skills.zero? ? 'none' : skills.to_s,
      version: @version,
      tally: runtime.tally
    ).each { |line| @io.puts(line) }
    @io.flush
    @repl&.replay(@sessions.recorded(runtime.id), theme: @theme)
  end
end
