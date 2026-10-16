# frozen_string_literal: true

require 'date'

class Riffer::Rig::Runtime::SystemPrompt
  # @rbs @base: String
  # @rbs @cwd: String
  # @rbs @sections: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]

  # @rbs base: String
  # @rbs cwd: String
  # @rbs sections: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs return: void
  def initialize(base, cwd, sections = {})
    @base = base
    @cwd = cwd
    @sections = sections
    freeze
  end

  # @rbs sections: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs return: Riffer::Rig::Runtime::SystemPrompt
  def with_sections(sections)
    self.class.new(@base, @cwd, sections)
  end

  # @rbs return: String
  def bare
    compose([])
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: String
  def render(runtime)
    compose(@sections.each_value.map { |section| section.call(runtime).to_s }.reject(&:empty?))
  end

  # @rbs session: Riffer::Agent::Session
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def refresh(session, runtime)
    # Upstream candidate: riffer resolves `instructions` once, in Agent.new, so
    # a per-turn system message has to be swapped into the session by hand.
    history = session.messages
    kept = history.first.is_a?(Riffer::Messages::System) ? history.drop(1) : history
    session.set([Riffer::Messages::System.new(render(runtime)), *kept])
  end

  private

  # @rbs sections: Array[String]
  # @rbs return: String
  def compose(sections)
    [@base, *sections, "Current date: #{Date.today}\nCurrent working directory: #{@cwd}"].join("\n\n")
  end
end
