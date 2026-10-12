# frozen_string_literal: true

module Riffer::Rig::Terminal::Columns
  extend self

  STYLE = /\e\[[\d;]*m/ #: Regexp

  TOKEN = /#{STYLE}|\X/ #: Regexp

  WIDE = /
    \A[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}\p{Emoji_Presentation}\u3000-\u303E\uFF01-\uFF60\uFFE0-\uFFE6]
    | \uFE0F
  /x #: Regexp

  ZERO = /\A(?:#{STYLE}|[\p{Mn}\p{Me}\p{Cf}])/ #: Regexp

  # @rbs text: String
  # @rbs return: Integer
  def width(text)
    tokens(text).sum { |token| span(token) }
  end

  # @rbs text: String
  # @rbs columns: Integer
  # @rbs return: String
  def head(text, columns)
    fit(tokens(text), columns).join
  end

  # @rbs text: String
  # @rbs columns: Integer
  # @rbs return: String
  def tail(text, columns)
    fit(tokens(text).reverse, columns).reverse.join
  end

  private

  # gsub without a block enumerates its matches as Strings, where scan types
  # each one as String | Array.
  # @rbs text: String
  # @rbs return: Array[String]
  def tokens(text)
    text.gsub(TOKEN).to_a
  end

  # Styles survive past the cut so a clipped span still reaches its reset.
  # @rbs tokens: Array[String]
  # @rbs columns: Integer
  # @rbs return: Array[String]
  def fit(tokens, columns)
    used = 0
    tokens.select { |token| STYLE.match?(token) || (used += span(token)) <= columns }
  end

  # @rbs token: String
  # @rbs return: Integer
  def span(token)
    return 2 if WIDE.match?(token)

    ZERO.match?(token) ? 0 : 1
  end
end
