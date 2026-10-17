# frozen_string_literal: true

module Riffer::Rig::Terminal::Echo
  extend self

  # @rbs prompt: String
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(prompt, theme:, width:)
    indent = Riffer::Rig::Terminal::Frame::PROMPT_COLUMNS
    wrapped = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent) << "#{pictured(prompt)}\n"
    "#{theme.pink(Riffer::Rig::Terminal::Frame::PROMPT)} #{wrapped.gsub(/\A\n+|\n+\z/, '').delete_prefix(' ' * indent)}"
  end

  private

  # @rbs prompt: String
  # @rbs return: String
  def pictured(prompt)
    prompt.gsub("\t", Riffer::Rig::Terminal::Markdown::TAB).split(/\r?\n/).map do |line|
      # A pasted prompt can carry control characters the terminal would act on.
      line.tr(Riffer::Rig::Terminal::LineEditor::CONTROLS, Riffer::Rig::Terminal::LineEditor::CONTROL_PICTURES)
    end.join("\n")
  end
end
