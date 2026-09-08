# frozen_string_literal: true

require 'kramdown'
require 'kramdown-parser-gfm'
require_relative 'unstable_tail'
require_relative 'highlighter'

module Riffer::Rig::UI::Markdown::Walker
  extend self

  # Pure pipeline stage: markdown source + terminal width → styled, hard-wrapped
  # lines. Unstable markdown syntax (half-typed tokens, open fences) streams as
  # raw text and joins the parse once stable. Falls back to plain text without
  # escapes when the Theme is disabled.
  INDENT_STEP = '  '
  BULLET = '• '
  ESCAPE_RE = /(?:\e\[[0-9;]*m|.)/m
  ANSI_RE = /\e\[[0-9;]*m/
  SMART_QUOTES = { ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', laquo: '«', raquo: '»' }.freeze

  def render(source, width:, theme:, highlighter:)
    return [] if source.empty?

    tail = Riffer::Rig::UI::Markdown::UnstableTail.split(source)[1]
    stable = tail.empty? ? source : source[0...-tail.length]

    lines = [] # : Array[String]
    Kramdown::Document.new(stable, input: 'GFM').root.children.each do |block|
      render_block(block, lines, width:, theme:, highlighter:)
    end
    unless tail.empty?
      tail.split("\n", -1).each_with_index do |raw, index|
        lines << raw if index.positive? || !raw.empty? || !lines.empty?
      end
    end
    lines
  end

  def visual_width(line)
    line.gsub(ANSI_RE, '').length
  end

  # Styled before wrapping so a visual width never splits from its escape
  # sequences; the scan treats escape sequences as zero-width.
  def wrap_styled(line, width)
    return [line] if line.empty? || visual_width(line) <= width

    out = [] # : Array[String]
    current = +''
    current_width = 0
    line.scan(ESCAPE_RE).each do |piece|
      piece_width = piece.start_with?("\e") ? 0 : 1
      if current_width + piece_width > width && current_width.positive?
        out << current
        current = +''
        current_width = 0
      end
      current << piece
      current_width += piece_width
    end
    out << current unless current.empty?
    out
  end

  def render_block(block, lines, width:, theme:, highlighter:, indent: '')
    case block.type
    when :header
      flush(lines, header_text(block, theme), width:, indent:)
    when :blockquote
      render_quote(block, lines, width:, theme:, highlighter:, indent:)
    when :codeblock
      render_codeblock(block, lines, width:, theme:, highlighter:, indent:)
    when :ul, :ol
      render_list(block, lines, width:, theme:, highlighter:, indent:)
    when :table
      render_table(block, lines, width:, theme:, highlighter:)
    when :hr
      lines << "#{indent}#{theme.grey('─' * [(width - indent.length), 3].max)}"
    when :blank
      lines << '' unless lines.empty?
    else
      flush(lines, render_inline(block.children, theme:, highlighter:), width:, indent:)
    end
  end

  def render_quote(block, lines, width:, theme:, highlighter:, indent:)
    body_width = [(width - indent.length - 2), 1].max
    block.children.each do |child|
      text = render_inline(child.children, theme:, highlighter:)
      wrap_styled(text, body_width).each { |line| lines << "#{indent}#{theme.grey('▌ ')}#{line}" }
    end
  end

  def render_codeblock(block, lines, width:, theme:, highlighter:, indent:)
    lang = block.options[:lang]
    lines << "#{indent}#{theme.grey('── ')}#{theme.purple(lang)}" if lang
    body = highlighter.highlight(block.value, lang)
    body.chomp.split("\n", -1).each do |code_line|
      flush(lines, code_line, width:, indent: "#{indent}#{INDENT_STEP}")
    end
  end

  def render_list(list, lines, width:, theme:, highlighter:, indent:)
    list.children.each_with_index do |item, index|
      marker = list.type == :ul ? BULLET : "#{index + 1}. "
      prefix = "#{indent}#{theme.grey(marker)}"
      continuation = "#{indent}#{' ' * visual_width(marker)}"
      lines.concat(render_list_item(item, width:, theme:, highlighter:, first: prefix, continuation:))
    end
  end

  def render_list_item(item, width:, theme:, highlighter:, first:, continuation:)
    out = [] # : Array[String]
    item.children.each_with_index do |child, index|
      child_indent = index.zero? ? '' : continuation
      case child.type
      when :p
        text = render_inline(child.children, theme:, highlighter:)
        flush(out, text, width:, indent: child_indent)
      when :ul, :ol
        render_list(child, out, width:, theme:, highlighter:, indent: continuation)
      else
        render_block(child, out, width:, theme:, highlighter:, indent: continuation)
      end
    end
    out.each_with_index.map { |line, i| i.zero? ? "#{first}#{line}" : line }
  end

  def render_table(table, lines, width:, theme:, highlighter:)
    alignments = table.options[:alignment] || []
    rows = table.children.flat_map(&:children)
    cells = rows.map { |row| row.children.map { |cell| render_inline(cell.children, theme:, highlighter:) } }
    widths = cells.transpose.map { |column| column.map { |cell| visual_width(cell) }.max || 1 }
    cells.each_with_index do |row, row_index|
      styled = row.each_with_index.map { |cell, i| pad(cell, widths[i], alignments[i]) }
      line = theme.bold(styled.join(theme.grey(' │ '))) if row_index.zero?
      line ||= styled.join(theme.grey(' │ '))
      flush(lines, line, width:, indent: '')
    end
  end

  def render_inline(children, theme:, highlighter:)
    children.map { |child| inline_text(child, theme:, highlighter:) }.join
  end

  def inline_text(element, theme:, highlighter:)
    case element.type
    when :strong then theme.bold(render_inline(element.children, theme:, highlighter:))
    when :em then theme.italic(render_inline(element.children, theme:, highlighter:))
    when :codespan then theme.paint(element.value, Riffer::Rig::UI::Palette::CYAN)
    when :a then "#{render_inline(element.children, theme:, highlighter:)} #{theme.grey("(#{element.attr['href']})")}"
    when :br then "\n"
    when :entity then [element.value.code_point].pack('U')
    when :smart_quote then SMART_QUOTES.fetch(element.value, element.value.to_s)
    when :typographic_sym, :text then element.value
    when :comment, :xml_comment then ''
    else render_inline(element.children, theme:, highlighter:)
    end
  end

  def header_text(block, theme)
    plain = Riffer::Rig::UI::Theme.new(enabled: false)
    text = render_inline(block.children, theme: plain, highlighter: plain)
    case block.options[:level]
    when 1 then theme.bold(theme.paint(text.upcase, Riffer::Rig::UI::Palette::PINK))
    when 2 then theme.bold(theme.paint(text, Riffer::Rig::UI::Palette::MAGENTA))
    else theme.paint(text, Riffer::Rig::UI::Palette::PURPLE)
    end
  end

  def pad(cell, width, alignment)
    shortfall = width - visual_width(cell)
    return cell if shortfall <= 0

    case alignment
    when :center
      left = shortfall / 2
      "#{' ' * left}#{cell}#{' ' * (shortfall - left)}"
    when :right
      "#{' ' * shortfall}#{cell}"
    else
      "#{cell}#{' ' * shortfall}"
    end
  end

  def flush(lines, text, width:, indent:)
    return if text.empty?

    wrapped = text.split("\n").flat_map { |segment| wrap_styled(segment, [(width - indent.length), 1].max) }
    wrapped.each { |segment| lines << "#{indent}#{segment}" }
  end
end
