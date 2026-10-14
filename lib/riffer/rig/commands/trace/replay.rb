# frozen_string_literal: true

module Riffer::Rig::Commands::Trace::Replay
  extend self

  SILENCE_THRESHOLD = 5.0 #: Float
  TIME_FORMAT = '%H:%M:%S.%L'
  UNSTAMPED = ' ' * 12 #: String
  LABEL_WIDTH = 8

  # Prompts, prose and tool arguments are replayed verbatim, and hosts print
  # command output raw: anything but tabs and newlines could drive a terminal.
  CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/ #: Regexp

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs return: Array[String]
  def lines(entries)
    turn = last_turn(entries)
    turn.zip([nil, *turn]).flat_map { |entry, previous| [silence(previous, entry), *activity(entry)] }.compact
  end

  private

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs return: Array[Riffer::Rig::Stores::MessageEntry]
  def last_turn(entries)
    recorded = entries.grep(Riffer::Rig::Stores::MessageEntry) #: Array[Riffer::Rig::Stores::MessageEntry]
    start = recorded.rindex { |entry| message(entry).instance_of?(Riffer::Messages::User) }
    start ? recorded.drop(start) : []
  end

  # @rbs entry: Riffer::Rig::Stores::MessageEntry
  # @rbs return: Riffer::Messages::Base
  def message(entry)
    Riffer::Rig::Runtime::Snapshot.message(entry.message)
  end

  # @rbs previous: Riffer::Rig::Stores::MessageEntry?
  # @rbs entry: Riffer::Rig::Stores::MessageEntry
  # @rbs return: String?
  def silence(previous, entry)
    started = previous&.recorded_time
    finished = entry.recorded_time
    return unless started && finished && finished - started >= SILENCE_THRESHOLD

    line(nil, 'silent', format('%.1fs', finished - started))
  end

  # @rbs entry: Riffer::Rig::Stores::MessageEntry
  # @rbs return: Array[String]
  def activity(entry)
    time = entry.recorded_time
    message = message(entry)
    case message
    when Riffer::Messages::Assistant
      prose(time, message) + message.tool_calls.map { |call| line(time, 'dispatch', "#{call.name} #{call.arguments}") }
    when Riffer::Messages::Tool
      [line(time, 'finish', message.error? ? "#{message.name} (#{message.error_type})" : message.name)]
    when Riffer::Rig::Runtime::JobNotification
      [line(time, 'notice', first_line(message.content))]
    else
      [line(time, 'prompt', first_line(message.content))]
    end
  end

  # @rbs time: Time?
  # @rbs message: Riffer::Messages::Assistant
  # @rbs return: Array[String]
  def prose(time, message)
    return [] if message.content.strip.empty?

    [line(time, message.has_tool_calls? ? 'preamble' : 'answer', first_line(message.content))]
  end

  # @rbs time: Time?
  # @rbs label: String
  # @rbs text: String
  # @rbs return: String
  def line(time, label, text)
    "#{time ? time.strftime(TIME_FORMAT) : UNSTAMPED}  #{label.ljust(LABEL_WIDTH)}  #{text.gsub(CONTROL, '')}"
  end

  # @rbs text: String
  # @rbs return: String
  def first_line(text)
    text.strip.lines.first.to_s.chomp
  end
end
