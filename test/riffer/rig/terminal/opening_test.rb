# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class OpenedRuntime
  attr_reader :id, :commands, :model, :cwd, :tally

  def initialize(commands: [])
    @id = 'opened'
    @commands = commands.map { |name| Riffer::Rig::Command.new(name, description: name, extension: :test) { nil } }
    @model = 'mock/test'
    @cwd = '/work/proj'
    @tally = nil
  end
end

class WatchingJobs
  attr_reader :watched

  def initialize = @watched = []

  def watch(runtime) = @watched << runtime
end

class RecordedSessions
  attr_reader :asked

  def initialize = @asked = []

  def recorded(id)
    @asked << id
    [:"#{id}-turn"]
  end
end

class ReplayingRepl
  attr_reader :replayed

  def initialize = @replayed = []

  def replay(recorded, theme:) = @replayed << [recorded, theme]
end

describe Riffer::Rig::Terminal::Opening do
  def setup
    @output = StringIO.new
    @theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    @sessions = RecordedSessions.new
  end

  def banner(runtime, jobs: nil, repl: nil)
    Riffer::Rig::Terminal::Opening.new(
      io: @output,
      theme: @theme,
      version: '9.9.9',
      sessions: @sessions,
      jobs: jobs,
      repl: repl
    ).call(runtime)
    @output.string
  end

  describe '#call' do
    it 'has the job counter watch the Runtime' do
      jobs = WatchingJobs.new
      runtime = OpenedRuntime.new

      banner(runtime, jobs: jobs)

      assert_equal [runtime], jobs.watched
    end

    it 'counts the skill commands in the banner' do
      assert_match(/skills\s+2$/, banner(OpenedRuntime.new(commands: %w[skill:tidy model skill:review])))
    end

    it 'shows none in the banner without skill commands' do
      assert_match(/skills\s+none$/, banner(OpenedRuntime.new(commands: %w[model])))
    end

    it 'prints the banner of the Runtime' do
      assert_match(%r{model\s+mock/test$}, banner(OpenedRuntime.new))
    end

    it "replays the turns recorded for the Runtime's session in the theme" do
      repl = ReplayingRepl.new

      banner(OpenedRuntime.new, repl: repl)

      assert_equal [[[:'opened-turn'], @theme]], repl.replayed
    end

    it 'reads no record without a Repl to replay it' do
      banner(OpenedRuntime.new)

      assert_empty @sessions.asked
    end
  end
end
