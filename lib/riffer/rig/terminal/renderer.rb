# frozen_string_literal: true

class Riffer::Rig::Terminal::Renderer
  # @rbs @io: Riffer::Rig::Terminal::_Output
  # @rbs @theme: Riffer::Rig::Terminal::Theme

  # @rbs io: Riffer::Rig::Terminal::_Output
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::Terminal::Theme.for(io))
    @io = io
    @theme = theme
  end

  # @rbs text: String
  # @rbs return: void
  def notice(text)
    render_block(@theme.grey(text))
  end

  # @rbs text: String
  # @rbs return: void
  def error(text)
    render_block(@theme.red(text))
  end

  # @rbs message: String
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message, level)
    level == :error ? error(message) : notice(message)
  end

  # @rbs return: void
  def prompt
    @io.puts
    @io.print("#{@theme.pink('›')} ")
    @io.flush
  end

  # @rbs line: String
  # @rbs return: void
  def echo(line)
    render_block("#{@theme.pink('›')} #{line}")
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: void
  def question(question, options, secret)
    @io.puts
    Riffer::Rig::Terminal::Question.lines(@theme, question, options).each { |line| @io.puts(line) }
    @io.print("#{@theme.pink('›')} #{@theme.grey('(hidden) ') if secret}")
    @io.flush
  end

  # @rbs return: void
  def newline
    @io.puts
    @io.flush
  end

  private

  # @rbs text: String
  # @rbs return: void
  def render_block(text)
    @io.puts
    @io.puts(text)
    @io.flush
  end
end
