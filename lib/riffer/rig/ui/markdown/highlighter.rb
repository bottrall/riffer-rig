# frozen_string_literal: true

require 'rouge'

# Maps rouge token types to Palette colors for code inside fenced blocks.
# Falls back to unstyled body text for an unknown or missing language.
class Riffer::Rig::UI::Markdown::Highlighter
  COLOR_FOR_TOKEN = {
    'Comment' => :grey,
    'Keyword' => :magenta,
    'Keyword::Constant' => :magenta,
    'Literal::String' => :cyan,
    'Literal::String::Affix' => :grey,
    'Literal::String::Delimiter' => :grey,
    'Literal::String::Interpol' => :magenta,
    'Literal::Number' => :blue,
    'Name::Function' => :blue,
    'Name::Constant' => :blue,
    'Name::Class' => :magenta,
    'Name::Tag' => :magenta,
    'Name::Builtin' => :cyan,
    'Name::Namespace' => :magenta,
    'Name::Variable' => :pink,
    'Operator::Word' => :magenta
  }.freeze

  def initialize(theme)
    @theme = theme
  end

  def highlight(source, language)
    lexer_class = Rouge::Lexer.find_fancy(language.to_s)
    return source unless lexer_class

    lexer_class.lex(source.gsub("\t", '  '), continue: false).map do |token, value|
      @theme.public_send(color_for(token), value)
    end.join
  end

  private

  def color_for(token)
    token.ancestors
         .filter_map { |ancestor| COLOR_FOR_TOKEN[ancestor.qualname] if ancestor.respond_to?(:qualname) }
         .first || :grey
  end
end
