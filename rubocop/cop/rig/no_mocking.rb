# frozen_string_literal: true

module RuboCop::Cop::Rig
  class NoMocking < RuboCop::Cop::Base
    MSG = "Don't mock code you own: inject a real lightweight fake instead. " \
          'Mock a genuine third party only at its API boundary.'

    OWNED_NAMESPACE = 'Riffer::Rig'

    def_node_matcher :singleton_patch, <<~PATTERN
      {
        (send $_ :define_singleton_method ...)
        (send (send $_ :singleton_class) :define_method ...)
        (send (send $_ :singleton_class) {:send :__send__} (sym :define_method) ...)
      }
    PATTERN

    def_node_matcher :class_patch, <<~PATTERN
      {
        (send $const :define_method ...)
        (send $const {:send :__send__} (sym :define_method) ...)
      }
    PATTERN

    def on_const(node)
      add_offense(node) if node.const_name.delete_prefix('::') == 'Minitest::Mock'
    end

    def on_send(node)
      add_offense(node) if node.method?(:stub) || patches_owned_code?(node)
    end

    private

    def patches_owned_code?(node)
      receiver = singleton_patch(node) || class_patch(node)
      receiver ? owned?(receiver, node) : false
    end

    def owned?(receiver, node)
      case receiver.type
      when :const then owned_constant?(receiver)
      when :lvar then built_from_owned_constant?(receiver, node)
      else false
      end
    end

    def owned_constant?(node)
      name = node.const_name.delete_prefix('::')
      name == OWNED_NAMESPACE || name.start_with?("#{OWNED_NAMESPACE}::")
    end

    # Only a local built in the patch's own scope has a type the cop can see:
    # a block parameter or a helper's return value could be anything.
    def built_from_owned_constant?(receiver, node)
      patch = node.parent&.any_block_type? && node.parent.send_node.equal?(node) ? node.parent : node
      scope = patch.each_ancestor(:any_block, :any_def).first || processed_source.ast
      scope.each_descendant(:lvasgn).any? do |assignment|
        value = assignment.expression
        assignment.name == receiver.children.first &&
          value&.send_type? && value.receiver&.const_type? && owned_constant?(value.receiver)
      end
    end
  end
end
