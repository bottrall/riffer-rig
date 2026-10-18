# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class OpenedRuntime
  attr_reader :id, :commands, :model, :cwd, :tally, :reasoning

  def initialize(commands: [], reasoning: nil)
    @id = 'opened'
    @commands = commands.map { |name| Riffer::Rig::Command.new(name, description: name, extension: :test) { nil } }
    @model = 'mock/test'
    @cwd = '/work/proj'
    @tally = nil
    @reasoning = reasoning
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
  attr_reader :watched, :replayed

  def initialize
    @watched = []
    @replayed = []
  end

  def watch(runtime) = @watched << runtime

  def replay(recorded, theme:) = @replayed << [recorded, theme]
end

describe Riffer::Rig::Terminal::Opening do
  def setup
    @output = StringIO.new
    @theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    @sessions = RecordedSessions.new
  end

  def banner(runtime, width: nil, jobs: nil, repl: nil)
    Riffer::Rig::Terminal::Opening.new(
      io: @output,
      theme: @theme,
      version: '9.9.9',
      sessions: @sessions,
      width: -> { width },
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

    it 'has the Repl watch the Runtime' do
      repl = ReplayingRepl.new
      runtime = OpenedRuntime.new

      banner(runtime, repl: repl)

      assert_equal [runtime], repl.watched
    end

    it 'counts the skill commands in the banner' do
      assert_match(/skills\s+2$/, banner(OpenedRuntime.new(commands: %w[skill:tidy model skill:review])))
    end

    it 'shows none in the banner without skill commands' do
      assert_match(/skills\s+none$/, banner(OpenedRuntime.new(commands: %w[model])))
    end

    it 'shows default in the banner without a reasoning level' do
      assert_match(/reasoning default$/, banner(OpenedRuntime.new))
    end

    it 'shows the reasoning level of the Runtime' do
      assert_match(/reasoning high$/, banner(OpenedRuntime.new(reasoning: 'high')))
    end

    it 'prints the banner of the Runtime' do
      assert_match(%r{model\s+mock/test$}, banner(OpenedRuntime.new))
    end

    it 'puts the reasoning row right after the model row' do
      lines = banner(OpenedRuntime.new(reasoning: 'high')).lines(chomp: true)

      assert_equal(
        lines.index { |line| line.include?('model ') } + 1,
        lines.index do |line|
          line.include?('reasoning')
        end
      )
    end

    it 'fits the banner to the measured width' do
      refute_includes banner(OpenedRuntime.new, width: 20), Riffer::Rig::Terminal::Banner::WORDMARK.first
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
