# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Inline
  extend self

  # An opener with no closer is searched for one as far as its span may run,
  # so without a ceiling a paragraph of openers costs quadratic time.
  SPAN_LIMIT = 1000 #: Integer

  # The trailing alternative matches whatever the others don't, so the matches
  # tile the text and a scan sees every character exactly once.
  TOKEN = %r{
    \\(?<escaped>[!-/:-@\[-`\{-~])
    | (?<ticks>`++)(?<code>.{1,#{SPAN_LIMIT}}?)(?<!`)\k<ticks>(?!`)
    | !?\[(?<label>[^\]]{0,#{SPAN_LIMIT}})\]
      \(\s*<?(?<target>(?:[^\s()<>]|\([^\s()<>]*\))+)>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)
    | \*\*\*(?=\S)(?<strong_em>.{1,#{SPAN_LIMIT}}?)(?<=\S)\*\*\*
    | \*\*(?=\S)(?<strong>.{1,#{SPAN_LIMIT}}?)(?<=\S)\*\*(?!\*)
    | (?<!\w)__(?=\S)(?<strong>.{1,#{SPAN_LIMIT}}?)(?<=\S)__(?!\w)
    | \*(?=[^\s*])(?<em>.{1,#{SPAN_LIMIT}}?)(?<=\S)\*
    | (?<!\w)_(?=[^\s_])(?<em>.{1,#{SPAN_LIMIT}}?)(?<=\S)_(?!\w)
    | (?<plain>[^\\`*_\[!]+|`+|.)
  }mx #: Regexp

  # A target is written into an OSC 8 sequence only when every byte is
  # printable ASCII, so it cannot terminate the sequence early, and only for
  # schemes that are safe to hand to the system opener.
  HYPERLINK = %r{\A(?:https?://|mailto:)[\x21-\x7e]+\z} #: Regexp

  # @rbs text: String
  # @rbs plain: bool
  # @rbs styles: Array[Symbol]
  # @rbs url: String?
  # @rbs return: Array[Riffer::Rig::Terminal::Markdown::Span]
  def parse(text, plain:, styles: [], url: nil)
    matches = text.enum_for(:scan, TOKEN).filter_map { Regexp.last_match } #: Array[MatchData]
    matches.flat_map { |match| token(match, plain: plain, styles: styles, url: url) }
  end

  private

  # @rbs match: MatchData
  # @rbs plain: bool
  # @rbs styles: Array[Symbol]
  # @rbs url: String?
  # @rbs return: Array[Riffer::Rig::Terminal::Markdown::Span]
  def token(match, plain:, styles:, url:)
    captures = match.named_captures(symbolize_names: true)
    literal = captures[:plain] || captures[:escaped]
    code = captures[:code]
    label = captures[:label]
    strong_em = captures[:strong_em]
    strong = captures[:strong]
    if literal
      [Riffer::Rig::Terminal::Markdown::Span.new(text: literal, styles: styles, url: url)]
    elsif code
      text = plain ? match[0] : code.strip
      [Riffer::Rig::Terminal::Markdown::Span.new(text: text, styles: [*styles, :code], url: url)]
    elsif label
      link(label, captures[:target].to_s, plain: plain, styles: styles)
    elsif strong_em
      parse(strong_em, plain: plain, styles: [*styles, :bold, :italic], url: url)
    elsif strong
      parse(strong, plain: plain, styles: [*styles, :bold], url: url)
    else
      parse(captures[:em].to_s, plain: plain, styles: [*styles, :italic], url: url)
    end
  end

  # @rbs label: String
  # @rbs target: String
  # @rbs plain: bool
  # @rbs styles: Array[Symbol]
  # @rbs return: Array[Riffer::Rig::Terminal::Markdown::Span]
  def link(label, target, plain:, styles:)
    return parse(label, plain: plain, styles: styles, url: target) if !plain && target.match?(HYPERLINK)

    spans = parse(label, plain: plain, styles: styles)
    return spans if label == target

    [*spans, Riffer::Rig::Terminal::Markdown::Span.new(text: " (#{target})", styles: styles)]
  end
end
