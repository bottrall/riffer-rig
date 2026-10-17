# frozen_string_literal: true

module Riffer::Rig::Terminal::Echo
  extend self

  # @rbs prompt: String
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(prompt, theme:, width:)
    # A pasted line can carry control characters the terminal would act on.
    pictured = Riffer::Rig::Terminal::LineEditor.new(before: prompt).printable_before
    indent = Riffer::Rig::Terminal::Frame::PROMPT_COLUMNS
    wrapped = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent) << "#{pictured}\n"
    "#{theme.pink(Riffer::Rig::Terminal::Frame::PROMPT)} #{wrapped.delete_prefix(' ' * indent).chomp}"
  end
end
