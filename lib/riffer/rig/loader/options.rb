# frozen_string_literal: true

class Riffer::Rig::Loader::Options
  # @dynamic model, extensions, skills, agents_md, tools, max_steps
  attr_reader :model #: String?
  attr_reader :extensions #: bool
  attr_reader :skills #: bool
  attr_reader :agents_md #: bool
  attr_reader :tools #: Array[String]?
  attr_reader :max_steps #: Integer?

  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs return: void
  def initialize(
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS
  )
    @model = model
    @extensions = extensions
    @skills = skills
    @agents_md = agents_md
    @tools = tools&.freeze
    @max_steps = max_steps
    freeze
  end
end
