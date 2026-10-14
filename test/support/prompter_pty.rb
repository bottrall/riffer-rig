# frozen_string_literal: true

require 'forwardable'
require 'stringio'
require 'timeout'
require_relative 'frame_pty'
require_relative 'key_pty'

class PrompterPty
  extend Forwardable

  def_delegators :@pty, :screen, :transcript

  attr_reader :prompter, :renderer, :host

  def initialize
    theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    @keys = KeyPty.new
    @pty = FramePty.new(columns: 100, rows: 24)
    @frame = Riffer::Rig::Terminal::Frame.new(io: @pty.slave, theme: theme)
    @frame.start
    @prompter = Riffer::Rig::Terminal::FramePrompter.new(frame: @frame, keys: @keys.pipeline.keys, theme: theme)
    # Notices do not go through the frame, so they are kept off its pty.
    @renderer = Riffer::Rig::Terminal::Renderer.new(io: StringIO.new, theme: theme)
    @host = Riffer::Rig::Terminal::Host.new(prompter: @prompter, renderer: @renderer)
  end

  def answering(bytes, &)
    @keys.type(bytes)
    Timeout.timeout(KeyPty::TIMEOUT_SECONDS, &)
  end

  def close
    @frame.stop
    @keys.close
    @pty.close
  end
end
