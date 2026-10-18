# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::KeyDecoder do
  def decode(string)
    decoder = Riffer::Rig::Terminal::KeyDecoder.new
    string.bytes.flat_map { |byte| decoder.push(byte) } + decoder.flush
  end

  def pairs(string)
    decode(string).map { |key| [key.name, key.text] }
  end

  def fed(string)
    Riffer::Rig::Terminal::KeyDecoder.new.tap { |decoder| string.bytes.each { |byte| decoder.push(byte) } }
  end

  describe '#pending?' do
    it 'pending? is false on a fresh decoder' do
      refute_predicate Riffer::Rig::Terminal::KeyDecoder.new, :pending?
    end

    it 'pending? is true mid-sequence' do
      assert_predicate fed("\e"), :pending?
    end

    it 'pending? is true mid-character' do
      assert_predicate fed("\xC3"), :pending?
    end
  end

  describe '#push' do
    it 'decodes Enter, Tab and Backspace' do
      assert_equal [[:enter, nil], [:tab, nil], [:backspace, nil]], pairs("\r\t\x7f")
    end

    it 'decodes line feed as a newline key and Ctrl-H as Backspace rather than as chords' do
      assert_equal [[:newline, nil], [:backspace, nil]], pairs("\n\x08")
    end

    it 'decodes multibyte characters as one text event' do
      assert_equal [[:text, 'é'], [:text, '🜁']], pairs('é🜁')
    end

    it 'decodes a character led by an 8-bit meta byte as text' do
      assert_equal [[:text, '€']], pairs('€')
    end

    it 'drops a byte that is not UTF-8' do
      assert_equal [[:text, 'a']], pairs("\xFFa")
    end

    it 'drops an incomplete character that another key interrupts' do
      assert_equal [[:text, 'a']], pairs("\xE2\x82a")
    end

    it 'drops a character that is still invalid after four bytes' do
      refute_predicate fed("\xF0\x80\x80\x80"), :pending?
    end

    it 'decodes a lone 8-bit meta byte that another key interrupts as its Alt chord' do
      assert_equal [[:alt_b, nil], [:alt_f, nil], [:text, 'a']], pairs("\xE2\xE6a")
    end

    it 'decodes Ctrl-chords by letter' do
      assert_equal [[:ctrl_a, nil], [:ctrl_c, nil], [:ctrl_z, nil]], pairs("\x01\x03\x1a")
    end

    it 'drops control bytes that are not chords' do
      assert_empty pairs("\x00\x1c\x1f")
    end

    it 'decodes printable characters into text events' do
      assert_equal [[:text, 'a'], [:text, 'b']], pairs('ab')
    end

    it 'decodes ASCII text as UTF-8' do
      assert_equal Encoding::UTF_8, decode('a').first.text.encoding
    end

    it 'decodes escape followed by b or f as Alt chords' do
      assert_equal [[:alt_b, nil], [:alt_f, nil]], pairs("\eb\ef")
    end

    it 'decodes escape followed by a character as escape then text' do
      assert_equal [[:escape, nil], [:text, 'a']], pairs("\ea")
    end

    it 'decodes escape followed by a carriage return as Alt-Enter' do
      assert_equal [[:alt_enter, nil]], pairs("\e\r")
    end

    it 'decodes escape followed by a line feed as escape then newline' do
      assert_equal [[:escape, nil], [:newline, nil]], pairs("\e\n")
    end

    it 'recovers when a control byte interrupts a sequence' do
      assert_equal [[:ctrl_c, nil], [:text, 'a']], pairs("\e[\x03a")
    end

    it 'restarts the sequence when an escape interrupts one' do
      assert_equal [[:up, nil]], pairs("\e[1\e[A")
    end

    it 'decodes arrow keys through CSI sequences' do
      assert_equal [[:up, nil], [:down, nil], [:right, nil], [:left, nil]], pairs("\e[A\e[B\e[C\e[D")
    end

    it 'decodes Ctrl with the horizontal arrows as chords' do
      assert_equal [[:ctrl_right, nil], [:ctrl_left, nil]], pairs("\e[1;5C\e[1;5D")
    end

    it 'decodes Alt with the horizontal arrows as chords' do
      assert_equal [[:alt_right, nil], [:alt_left, nil]], pairs("\e[1;3C\e[1;3D")
    end

    it 'decodes other modified sequences by the final byte' do
      assert_equal [[:right, nil], [:up, nil], [:shift_tab, nil]], pairs("\e[1;2C\e[1;5A\e[Z")
    end

    it 'decodes tilde-terminated CSI sequences' do
      assert_equal [[:home, nil], [:insert, nil], [:delete, nil], [:page_up, nil], [:page_down, nil]],
                   pairs("\e[1~\e[2~\e[3~\e[5~\e[6~")
    end

    it 'decodes Shift-Enter through a CSI-u sequence' do
      assert_equal [[:shift_enter, nil]], pairs("\e[13;2u")
    end

    it 'decodes Alt-Enter through a CSI-u sequence' do
      assert_equal [[:alt_enter, nil]], pairs("\e[13;3u")
    end

    it 'decodes an Enter CSI-u sequence without a modifier as Enter' do
      assert_equal [[:enter, nil]], pairs("\e[13u")
    end

    it 'decodes Ctrl-Shift-Enter through a CSI-u sequence as Enter' do
      assert_equal [[:enter, nil]], pairs("\e[13;6u")
    end

    it 'decodes Ctrl-J through a CSI-u sequence as a newline' do
      assert_equal [[:newline, nil]], pairs("\e[106;5u")
    end

    it 'decodes Ctrl-I through a CSI-u sequence as a tab' do
      assert_equal [[:tab, nil]], pairs("\e[105;5u")
    end

    it 'decodes Ctrl-H through a CSI-u sequence as a backspace' do
      assert_equal [[:backspace, nil]], pairs("\e[104;5u")
    end

    it 'decodes Ctrl-M through a CSI-u sequence as Enter' do
      assert_equal [[:enter, nil]], pairs("\e[109;5u")
    end

    it 'decodes Ctrl-chords through CSI-u sequences by letter' do
      assert_equal [[:ctrl_w, nil], [:ctrl_c, nil]], pairs("\e[119;5u\e[99;5u")
    end

    it 'decodes Alt-chords through CSI-u sequences by letter' do
      assert_equal [[:alt_b, nil], [:alt_f, nil]], pairs("\e[98;3u\e[102;3u")
    end

    it 'decodes a lone escape through a CSI-u sequence' do
      assert_equal [[:escape, nil]], pairs("\e[27u")
    end

    it 'decodes Shift-Tab through a CSI-u sequence' do
      assert_equal [[:shift_tab, nil]], pairs("\e[9;2u")
    end

    it 'decodes Ctrl-Tab through a CSI-u sequence as a tab' do
      assert_equal [[:tab, nil]], pairs("\e[9;5u")
    end

    it 'decodes Ctrl-Backspace through a CSI-u sequence as a backspace' do
      assert_equal [[:backspace, nil]], pairs("\e[127;5u")
    end

    it 'decodes Alt-Backspace through a CSI-u sequence as a backspace' do
      assert_equal [[:backspace, nil]], pairs("\e[127;3u")
    end

    it 'drops CSI-u sequences for keys without a chord' do
      assert_empty pairs("\e[32;5u\e[49;2u")
    end

    it 'drops unknown CSI sequences' do
      assert_empty pairs("\e[?u\e[999~")
    end

    it 'drops a tilde-terminated CSI sequence with no parameter' do
      assert_empty pairs("\e[~")
    end

    it 'decodes Home and End through CSI and SS3 sequences' do
      assert_equal [[:home, nil], [:end, nil], [:home, nil], [:end, nil]], pairs("\e[H\e[F\eOH\eOF")
    end

    it 'drops unknown SS3 sequences' do
      assert_empty pairs("\eOx")
    end

    it 'decodes a bracketed paste into one event carrying the text' do
      assert_equal [[:paste, "line one\nline two"]], pairs("\e[200~line one\nline two\e[201~")
    end

    it 'holds a paste open across pushes until the end marker' do
      decoder = fed("\e[200~hel")
      events = "lo\e[201~".bytes.flat_map { |byte| decoder.push(byte) }

      assert_equal [Riffer::Rig::Terminal::Key.new(:paste, 'hello')], events
    end

    it 'decodes a carriage return inside a paste as a newline' do
      assert_equal [[:paste, "one\ntwo\n"]], pairs("\e[200~one\rtwo\r\e[201~")
    end

    it 'decodes a carriage return and line feed inside a paste as one newline' do
      assert_equal [[:paste, "one\ntwo"]], pairs("\e[200~one\r\ntwo\e[201~")
    end

    it 'drops bytes that are not UTF-8 from a paste' do
      assert_equal [[:paste, 'ab']], pairs("\e[200~a\xFF\xF1b\e[201~")
    end
  end

  describe '#flush' do
    it 'flushes nothing from an unterminated paste' do
      assert_empty fed("\e[200~hel").flush
    end

    it 'keeps an unterminated paste open' do
      decoder = fed("\e[200~hel")
      decoder.flush
      events = "lo\e[201~".bytes.flat_map { |byte| decoder.push(byte) }

      assert_equal [Riffer::Rig::Terminal::Key.new(:paste, 'hello')], events
    end

    it 'decodes a lone escape once the reader gives up on a sequence' do
      assert_equal [Riffer::Rig::Terminal::Key.new(:escape)], fed("\e").flush
    end

    it 'decodes a lone 8-bit meta byte as its Alt chord' do
      assert_equal [Riffer::Rig::Terminal::Key.new(:alt_f)], fed("\xE6").flush
    end

    it 'flushes nothing from a lone byte that is not a meta key' do
      assert_empty fed("\xE1").flush
    end

    it 'flushes nothing from an incomplete character' do
      assert_empty fed("\xE2\x82").flush
    end

    it 'flushes nothing from an unterminated CSI sequence' do
      assert_empty fed("\e[1").flush
    end

    it 'returns the decoder to ground' do
      decoder = fed("\e[1")
      decoder.flush

      assert_equal [Riffer::Rig::Terminal::Key.new(:text, 'A')], decoder.push('A'.ord)
    end
  end
end
