# frozen_string_literal: true

module RuboCop::Cop::Rig
  class NoDataDefine < RuboCop::Cop::Base
    MSG = 'Write a value object as a frozen PORO (see Mcp::Declaration), not `Data.define` or `Struct.new`.'

    RESTRICT_ON_SEND = %i[define new].freeze

    def_node_matcher :value_class_factory?, <<~PATTERN
      {
        (send (const {nil? cbase} :Data) :define ...)
        (send (const {nil? cbase} :Struct) :new ...)
      }
    PATTERN

    def on_send(node)
      add_offense(node) if value_class_factory?(node)
    end
  end
end
