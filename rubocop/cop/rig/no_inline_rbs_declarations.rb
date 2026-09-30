# frozen_string_literal: true

module RuboCop::Cop::Rig
  class NoInlineRbsDeclarations < RuboCop::Cop::Base
    MSG = 'Move `@rbs!` declarations (interfaces, type aliases) to sig/manual/.'

    def on_new_investigation
      processed_source.comments
                      .select { |comment| comment.text.match?(/\A#\s*@rbs!/) }
                      .each { |comment| add_offense(comment) }
    end
  end
end
