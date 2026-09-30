# frozen_string_literal: true

module RuboCop::Cop::Rig
  class NoInheritance < RuboCop::Cop::Base
    MSG = "Compose, don't inherit: pass collaborators in, share code through a mixin, and describe " \
          'contracts as RBS interfaces in sig/manual/. Only framework-mandated parents are allowed; ' \
          'for another framework parent, add a scoped disable with a reason.'

    ALLOWED_PARENTS = %w[
      Riffer::Agent
      Riffer::Guardrail
      Riffer::Skills::Backend
      Riffer::Tool
      Riffer::Tools::Runtime
    ].freeze

    def on_class(node)
      parent = node.parent_class
      return unless parent&.const_type?
      return if allowed?(parent.const_name.delete_prefix('::'))

      add_offense(parent)
    end

    private

    def allowed?(name)
      ALLOWED_PARENTS.include?(name) || name.end_with?('Error')
    end
  end
end
