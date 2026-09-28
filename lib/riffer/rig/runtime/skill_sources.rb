# frozen_string_literal: true

# Upstream candidate: riffer's Skills::Config takes a single backend, so the
# sources every extension registers are merged into one here.
class Riffer::Rig::Runtime::SkillSources < Riffer::Skills::Backend
  # @rbs @backends: Array[Riffer::Skills::Backend]

  # @rbs backends: Array[Riffer::Skills::Backend]
  # @rbs return: void
  def initialize(backends)
    super()
    @backends = backends
  end

  # @rbs return: Array[Riffer::Skills::Frontmatter]
  def list_skills
    @backends.flat_map(&:list_skills).uniq(&:name)
  end

  # @rbs name: String
  # @rbs return: String
  def read_skill(name)
    backend = @backends.find { |source| source.list_skills.any? { |skill| skill.name == name } }
    raise Riffer::ArgumentError, "Skill not found: '#{name}'" unless backend

    backend.read_skill(name)
  end
end
