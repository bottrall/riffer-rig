# frozen_string_literal: true

module RuboCop::Cop::Rig
  class NoInheritance < RuboCop::Cop::Base
    MSG = "Compose, don't inherit: pass collaborators in, share code through a mixin, and describe " \
          'contracts as RBS interfaces in sig/manual/. Only framework-mandated parents are allowed; ' \
          'for another framework parent, add a scoped disable with a reason.'

    ALLOWED_PARENTS = %w[
      Exception
      Riffer::Agent
      Riffer::Guardrail
      Riffer::Messages::User
      Riffer::Skills::Backend
      Riffer::Tool
      Riffer::Tools::Runtime
    ].freeze

    def on_class(node)
      parent = node.parent_class
      return unless parent
      return if parent.const_type? && allowed?(parent.const_name.delete_prefix('::'))

      add_offense(parent)
    end

    private

    def allowed?(name)
      ALLOWED_PARENTS.include?(name) || core_standard_error?(name)
    end

    # Only core classes, defined in C, resolve the same in every process: a
    # gem's or the project's own error classes aren't loaded when the cop runs.
    def core_standard_error?(name)
      return false unless Object.const_defined?(name) && Object.const_source_location(name) == []

      parent = Object.const_get(name)
      parent.is_a?(Class) && parent <= StandardError
    end
  end
end
