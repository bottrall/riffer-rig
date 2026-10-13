# frozen_string_literal: true

class Riffer::Rig::Terminal::FramePrompter
  HIDDEN = '(hidden)' #: String

  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @keys: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @theme: Riffer::Rig::Terminal::Theme

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs keys: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: void
  def initialize(frame:, keys:, theme:)
    @frame = frame
    @keys = keys
    @theme = theme
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question, options:, secret:)
    asked = Riffer::Rig::Terminal::Question.lines(@theme, question, options)
    @frame.append(['', *asked, *(@theme.grey(HIDDEN) if secret)].join("\n"))
    editor = read(secret)
    return nil unless editor

    @frame.append("#{prompt} #{editor.printable_before}#{editor.printable_after}") unless secret
    editor.text
  end

  private

  # @rbs secret: bool
  # @rbs return: Riffer::Rig::Terminal::LineEditor?
  def read(secret)
    editor = Riffer::Rig::Terminal::LineEditor.new
    loop do
      key = @keys.pop
      return nil if key.nil? || key.name == :ctrl_d
      # Raw mode delivers Ctrl-C as a key instead of the signal a blocking
      # read is interrupted by.
      raise Interrupt if key.name == :ctrl_c
      return editor if key.name == :enter

      editor = editor.press(key)
      @frame.input(editor) unless secret
    end
  ensure
    @frame.input(Riffer::Rig::Terminal::LineEditor.new)
  end

  # @rbs return: String
  def prompt
    @theme.pink(Riffer::Rig::Terminal::Frame::PROMPT)
  end
end
