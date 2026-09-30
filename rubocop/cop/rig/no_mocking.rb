# frozen_string_literal: true

module RuboCop::Cop::Rig
  class NoMocking < RuboCop::Cop::Base
    MSG = "Don't mock code you own: inject a real lightweight fake instead. " \
          'Mock a genuine third party only at its API boundary.'

    def on_const(node)
      add_offense(node) if node.const_name.delete_prefix('::') == 'Minitest::Mock'
    end

    def on_send(node)
      add_offense(node) if node.method?(:stub)
    end
  end
end
