# frozen_string_literal: true

require 'date'

class Riffer::Rig::Runtime::SystemPrompt
  ENVIRONMENT = :environment #: Symbol

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
    render({ ENVIRONMENT => environment })
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: Hash[Symbol, String]
  def values(runtime)
    rendered = @sections.transform_values { |section| section.call(runtime).to_s }.reject { |_name, text| text.empty? }
    rendered.merge(ENVIRONMENT => environment)
  end

  # @rbs values: Hash[Symbol, String]
  # @rbs return: String
  def render(values)
    [@base, *values.values].join("\n\n")
  end

  private

  # @rbs return: String
  def environment
    "Current date: #{Date.today}\nCurrent working directory: #{@cwd}"
  end
end
