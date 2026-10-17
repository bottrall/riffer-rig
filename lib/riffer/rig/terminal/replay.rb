# frozen_string_literal: true

module Riffer::Rig::Terminal::Replay
  extend self

  NOTICE = 'Turns recorded by an older version or damaged on disk are not shown.'

  # @rbs recorded: Array[Riffer::Rig::Terminal::Replay::_Recorded]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(recorded, theme:, width:)
    # A notification without a follow-up count was delivered within the turn
    # of a prompt, so it opens no turn of its own.
    kept = recorded.reject do |entry|
      entry.message[Riffer::Rig::Runtime::JobNotification::MARKER] && !entry.message[:follow_up_exits]
    end
    turns = kept.slice_before { |entry| entry.message[:role].to_s == 'user' }.map { |chunk| turn(chunk, theme, width) }
    replayed = turns.compact.map do |past|
      "#{past.heading}#{Riffer::Rig::Terminal::TurnReport.call(past, nil, theme: theme, width: width)}"
    end
    indent = ' ' * Riffer::Rig::Terminal::TurnReport::INDENT
    [*replayed, *("\n#{theme.dim("#{indent}#{NOTICE}")}\n" if replayed.size < turns.size)].join
  end

  private

  # @rbs chunk: Array[Riffer::Rig::Terminal::Replay::_Recorded]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Riffer::Rig::Terminal::Replay::Turn?
  def turn(chunk, theme, width)
    started = chunk.first&.recorded_time
    ended = chunk.last&.recorded_time
    opener, *rest = chunk.map { |entry| message(entry) }
    heading = heading(opener, theme, width)
    return nil unless started && ended && heading && rest.all?

    replies = rest.grep(Riffer::Messages::Assistant) #: Array[Riffer::Messages::Assistant]
    Turn.new(
      heading: heading,
      answer: replies.reject(&:has_tool_calls?).map(&:content).grep(/\S/).last,
      stats: Riffer::Rig::Terminal::TurnBuffer::Stats.new(
        steps: replies.size,
        wall_time: ended - started,
        usage: Riffer::Rig::Runtime::Usage.sum(replies)
      )
    )
  end

  # @rbs opener: Riffer::Messages::Base?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String?
  def heading(opener, theme, width)
    case opener
    when Riffer::Rig::Runtime::JobNotification
      exits = opener.follow_up_exits
      notice = Riffer::Rig::Terminal::JobExitNotice.call(exits) if exits
      "\n#{theme.grey(Riffer::Rig::Terminal::TurnReport.wrap(notice, width))}\n" if notice
    when Riffer::Messages::User
      "\n#{Riffer::Rig::Terminal::Echo.call(opener.content, theme: theme, width: width)}\n"
    end
  end

  # @rbs entry: Riffer::Rig::Terminal::Replay::_Recorded
  # @rbs return: Riffer::Messages::Base?
  def message(entry)
    hash = entry.message
    Riffer::Rig::Runtime::Snapshot.message(hash) if hash[:content].is_a?(String)
  # riffer checks a message hash only by rebuilding it, and a damaged one
  # fails wherever the damage sits, not with one error.
  rescue StandardError
    nil
  end
end
