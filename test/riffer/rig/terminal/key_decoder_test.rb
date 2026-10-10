# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::KeyDecoder do
  def decode(string)
    decoder = Riffer::Rig::Terminal::KeyDecoder.new
    string.chars.flat_map { |char| decoder.push(char) } + decoder.flush
  end

  def pairs(string)
    decode(string).map { |key| [key.name, key.text] }
  end

  it 'decodes printable characters into text events' do
    assert_equal [[:text, 'a'], [:text, 'b']], pairs('ab')
  end

  it 'decodes multibyte characters as one text event' do
    assert_equal [[:text, 'é'], [:text, '🜁']], pairs('é🜁')
  end

  it 'decodes Enter, Tab and Backspace' do
    assert_equal [[:enter, nil], [:tab, nil], [:backspace, nil]], pairs("\r\t\x7f")
  end

  it 'decodes Ctrl-chords by letter' do
    assert_equal [[:ctrl_a, nil], [:ctrl_c, nil], [:ctrl_z, nil]], pairs("\x01\x03\x1a")
  end

  it 'decodes arrow keys through CSI sequences' do
    assert_equal [[:up, nil], [:down, nil], [:right, nil], [:left, nil]], pairs("\e[A\e[B\e[C\e[D")
  end

  it 'decodes Home and End through CSI and SS3 sequences' do
    assert_equal [[:home, nil], [:end, nil], [:home, nil], [:end, nil]], pairs("\e[H\e[F\eOH\eOF")
  end

  it 'decodes tilde-terminated CSI sequences' do
    assert_equal [[:home, nil], [:insert, nil], [:delete, nil], [:page_up, nil], [:page_down, nil]],
                 pairs("\e[1~\e[2~\e[3~\e[5~\e[6~")
  end

  it 'decodes modified sequences by the final byte' do
    assert_equal [[:right, nil], [:shift_tab, nil]], pairs("\e[1;5C\e[Z")
  end

  it 'decodes a bracketed paste into one event carrying the text' do
    assert_equal [[:paste, "line one\nline two"]], pairs("\e[200~line one\nline two\e[201~")
  end

  it 'holds a paste open across pushes until the end marker' do
    decoder = Riffer::Rig::Terminal::KeyDecoder.new
    "\e[200~hel".chars.each { |char| decoder.push(char) }
    events = "lo\e[201~".chars.flat_map { |char| decoder.push(char) }

    assert_equal [Riffer::Rig::Terminal::Key.new(:paste, 'hello')], events
  end

  it 'decodes a lone escape once the reader gives up on a sequence' do
    decoder = Riffer::Rig::Terminal::KeyDecoder.new
    decoder.push("\e")

    assert_equal [Riffer::Rig::Terminal::Key.new(:escape)], decoder.flush
  end

  it 'decodes escape followed by a character as escape then text' do
    assert_equal [[:escape, nil], [:text, 'a']], pairs("\ea")
  end

  it 'drops unknown CSI sequences' do
    assert_empty pairs("\e[?u\e[999~")
  end

  it 'recovers when a control byte interrupts a sequence' do
    assert_equal [[:ctrl_c, nil], [:text, 'a']], pairs("\e[\x03a")
  end

  it 'pending? is false on a fresh decoder' do
    refute_predicate Riffer::Rig::Terminal::KeyDecoder.new, :pending?
  end

  it 'pending? is true mid-sequence' do
    decoder = Riffer::Rig::Terminal::KeyDecoder.new
    decoder.push("\e")

    assert_predicate decoder, :pending?
  end
end
