# frozen_string_literal: true

class Riffer::Rig::Terminal::Interrupter
  STOPPING = 'stopping…' #: String

  MARKER = 'interrupted' #: String

  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @theme: Riffer::Rig::Terminal::Theme

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: void
  def initialize(frame:, theme:)
    @frame = frame
    @theme = theme
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def cancel(runtime)
    # The turn can end the moment the Runtime is cancelled, and a status set
    # after that would outlive the turn it describes.
    @frame.status(@theme.dim(STOPPING))
    runtime.cancel
  end

  # @rbs turn: Riffer::Rig::Terminal::TurnBuffer
  # @rbs return: void
  def finish(turn)
    @frame.status('')
    @frame.append([*turn.answer&.rstrip, @theme.dim(MARKER)].join("\n")) if turn.interrupted?
  end
end
