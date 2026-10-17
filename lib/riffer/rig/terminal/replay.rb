# frozen_string_literal: true

module Riffer::Rig::Terminal::Replay
  extend self

  NOTICE = 'Turns recorded by an older version or damaged on disk are not shown.'

  # @rbs recorded: Array[Riffer::Rig::Terminal::Replay::_Recorded]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(recorded, theme:, width:)
    typed = recorded.reject { |entry| entry.message[Riffer::Rig::Runtime::JobNotification::MARKER] }
    turns = typed.slice_before { |entry| entry.message[:role].to_s == 'user' }.map { |chunk| turn(chunk) }
    replayed = turns.compact.map do |past|
      echo = Riffer::Rig::Terminal::Echo.call(past.prompt, theme: theme, width: width)
      "\n#{echo}\n#{Riffer::Rig::Terminal::TurnReport.call(past, nil, theme: theme, width: width)}"
    end
    indent = ' ' * Riffer::Rig::Terminal::TurnReport::INDENT
    [*replayed, *("\n#{theme.dim("#{indent}#{NOTICE}")}\n" if replayed.size < turns.size)].join
  end

  private

  # @rbs chunk: Array[Riffer::Rig::Terminal::Replay::_Recorded]
  # @rbs return: Riffer::Rig::Terminal::Replay::Turn?
  def turn(chunk)
    started = chunk.first&.recorded_time
    ended = chunk.last&.recorded_time
    prompt, *rest = chunk.map { |entry| message(entry) }
    return nil unless started && ended && prompt.is_a?(Riffer::Messages::User) && rest.all?

    replies = rest.grep(Riffer::Messages::Assistant) #: Array[Riffer::Messages::Assistant]
    Turn.new(
      prompt: prompt.content,
      answer: replies.reject(&:has_tool_calls?).map(&:content).grep(/\S/).last,
      stats: Riffer::Rig::Terminal::TurnBuffer::Stats.new(
        steps: replies.size,
        wall_time: ended - started,
        usage: Riffer::Rig::Runtime::Usage.sum(replies)
      )
    )
  end

  # @rbs entry: Riffer::Rig::Terminal::Replay::_Recorded
  # @rbs return: Riffer::Messages::Base?
  def message(entry)
    hash = entry.message
    Riffer::Messages::Base.from_hash(hash) if hash[:content].is_a?(String)
  # riffer checks a message hash only by rebuilding it, and a damaged one
  # fails wherever the damage sits, not with one error.
  rescue StandardError
    nil
  end
end
