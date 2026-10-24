# frozen_string_literal: true

module Riffer::Rig::Terminal::StatusBar
  extend self

  IDLE_GLYPH = '·' #: String

  IDLE_STATE = 'idle' #: String

  GLYPH_WIDTH = 1 #: Integer

  STATE_WIDTH = 7 #: Integer

  REASONING_WIDTH = 7 #: Integer

  CLOCK_WIDTH = 5 #: Integer

  TOKEN_WIDTH = 6 #: Integer

  # The unit rides in the down slot's box, so the constant `tok` never shifts
  # what follows it.
  DOWN_WIDTH = 10 #: Integer

  COST_WIDTH = 8 #: Integer

  JOBS_WIDTH = 6 #: Integer

  SEPARATOR = ' ' #: String

  SLOTS = %i[glyph state reasoning clock up down cost jobs].freeze #: Array[Symbol]

  # A narrow terminal sheds whole slots from the left in this order — the
  # reasoning level first, since it is static and recoverable via /reasoning,
  # then the clock, then the cost, then the tokens, then the state — so the
  # dynamic slots and the jobs count at the right edge survive longest.
  KEEP_SETS = [
    SLOTS,
    SLOTS - %i[reasoning],
    SLOTS - %i[reasoning clock],
    SLOTS - %i[reasoning clock cost],
    SLOTS - %i[reasoning clock cost up down],
    %i[glyph jobs]
  ].freeze #: Array[Array[Symbol]]

  # @rbs reasoning: String?
  # @rbs clock: String
  # @rbs up_tokens: Integer
  # @rbs down_tokens: Integer
  # @rbs cost: Float
  # @rbs jobs: Integer
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs room: Integer
  # @rbs return: String
  def idle(reasoning:, clock:, up_tokens:, down_tokens:, cost:, jobs:, theme:, room:)
    slots = segments(IDLE_GLYPH, IDLE_STATE, reasoning, clock, up_tokens, down_tokens, cost, jobs)
    theme.dim(kept(slots, room).values.join(SEPARATOR))
  end

  # @rbs glyph: String
  # @rbs state: String
  # @rbs reasoning: String?
  # @rbs clock: String
  # @rbs up_tokens: Integer
  # @rbs down_tokens: Integer
  # @rbs cost: Float
  # @rbs jobs: Integer
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs room: Integer
  # @rbs return: String
  def working(glyph:, state:, reasoning:, clock:, up_tokens:, down_tokens:, cost:, jobs:, theme:, room:)
    slots = segments(glyph, state, reasoning, clock, up_tokens, down_tokens, cost, jobs)
    kept(slots, room).map { |key, text| color(text, key, theme) }.join(SEPARATOR)
  end

  private

  # @rbs glyph: String
  # @rbs state: String
  # @rbs reasoning: String?
  # @rbs clock: String
  # @rbs up_tokens: Integer
  # @rbs down_tokens: Integer
  # @rbs cost: Float
  # @rbs jobs: Integer
  # @rbs return: Hash[Symbol, String]
  def segments(glyph, state, reasoning, clock, up_tokens, down_tokens, cost, jobs)
    {
      glyph: field(glyph, GLYPH_WIDTH),
      state: field(state, STATE_WIDTH),
      reasoning: field(reasoning || Riffer::Rig::Runtime::DEFAULT_REASONING_LABEL, REASONING_WIDTH),
      clock: field(clock, CLOCK_WIDTH),
      up: field("↑#{Riffer::Rig::Terminal::Count.call(up_tokens)}", TOKEN_WIDTH),
      down: field("↓#{Riffer::Rig::Terminal::Count.call(down_tokens)} tok", DOWN_WIDTH),
      cost: field(format('~$%.4f', cost), COST_WIDTH),
      jobs: field("#{jobs} #{jobs == 1 ? 'job' : 'jobs'}", JOBS_WIDTH)
    }
  end

  # @rbs slots: Hash[Symbol, String]
  # @rbs room: Integer
  # @rbs return: Hash[Symbol, String]
  def kept(slots, room)
    keys = KEEP_SETS.find { |set| fits?(set, slots, room) } || KEEP_SETS.last
    keys.to_h { |key| [key, slots.fetch(key)] }
  end

  # @rbs text: String
  # @rbs width: Integer
  # @rbs return: String
  def field(text, width)
    Riffer::Rig::Terminal::Columns.head(text.ljust(width), width)
  end

  # @rbs set: Array[Symbol]
  # @rbs slots: Hash[Symbol, String]
  # @rbs room: Integer
  # @rbs return: bool
  def fits?(set, slots, room)
    Riffer::Rig::Terminal::Columns.width(set.map { |key| slots.fetch(key) }.join(SEPARATOR)) <= room
  end

  # @rbs text: String
  # @rbs key: Symbol
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def color(text, key, theme)
    case key
    when :glyph, :cost then theme.cyan(text)
    when :jobs then theme.magenta(text)
    when :up, :down then theme.dim(text)
    else text
    end
  end
end
