# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown do
  def render(source, enabled: false, width: 40)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: enabled)
    Riffer::Rig::Terminal::Markdown.render(source, theme: theme, width: width)
  end

  def fixture(name)
    File.read(File.expand_path("../../../fixtures/markdown/#{name}", __dir__))
  end

  describe 'golden output' do
    it 'renders the answer in colour' do
      assert_equal fixture('answer.color.ansi'), render(fixture('answer.md'), enabled: true, width: 60)
    end

    it 'renders the answer without colour' do
      assert_equal fixture('answer.plain.txt'), render(fixture('answer.md'), width: 60)
    end

    it 'renders the answer in colour at a narrow width' do
      assert_equal fixture('answer.narrow.ansi'), render(fixture('answer.md'), enabled: true, width: 24)
    end

    it 'renders the answer without colour at a narrow width' do
      assert_equal fixture('answer.narrow.txt'), render(fixture('answer.md'), width: 24)
    end

    it 'emits no escape sequence without colour' do
      refute_includes render(fixture('answer.md'), width: 60), "\e"
    end
  end

  describe 'untrusted input' do
    it 'replaces invalid bytes instead of raising' do
      assert_equal "abc ��31m def\n", render("abc \xff\x9b31m def")
    end

    it 'transcodes a source in another encoding' do
      assert_equal "café\n", render("caf\xE9".b.force_encoding(Encoding::ISO_8859_1))
    end

    it 'treats a carriage return line feed as one line ending' do
      assert_equal "a b\n\nc\n", render("a\r\nb\r\n\r\nc")
    end

    it 'strips an escape sequence down to inert text' do
      assert_equal "a[31mb\n", render("a\e[31mb")
    end

    it 'strips c1 control characters' do
      assert_equal "a31mb\n", render("a\u009b31mb")
    end

    it 'strips the bell and backspace' do
      assert_equal "ab\n", render("a\a\bb")
    end

    it 'strips control characters inside a fence' do
      assert_equal "│ a[2Jb\n", render("```\na\e[2Jb\n```")
    end

    it 'cannot close a hyperlink early from its target' do
      assert_equal(
        "\e]8;;https://a]8;;https://evil\e\\\e[4m\e[38;2;77;124;255mx\e[0m\e[0m\e]8;;\e\\\n",
        render("[x](https://a\e]8;;https://evil\a)", enabled: true)
      )
    end

    it 'expands a tab to four spaces' do
      assert_equal "│     x\n", render("```\n\tx\n```")
    end

    it 'prints html as text' do
      assert_equal "<script>alert(1)</script>\n", render('<script>alert(1)</script>')
    end

    it 'terminates at a width of one' do
      assert_equal "• a\n  b\n┃ c\n", render("- a b\n> c", width: 1)
    end

    it 'treats a width below one as one' do
      assert_equal "a\nb\n", render('ab', width: 0)
    end

    it 'prints nesting past the limit as text instead of recursing' do
      assert_equal "#{'┃ ' * 17}#{'>' * 4983} deep\n", render("#{'>' * 5000} deep", width: nil)
    end
  end

  describe 'horizontal rules' do
    it 'draws a rule across the width' do
      assert_equal "─────\n", render('---', width: 5)
    end

    it 'paints the rule' do
      assert_equal "\e[2m─────\e[0m\n", render('---', enabled: true, width: 5)
    end

    it 'draws a fixed-length rule when no width is known' do
      assert_equal "#{'─' * 40}\n", render('---', width: nil)
    end
  end

  describe 'paragraphs' do
    it 'joins the lines of a paragraph and wraps at the width' do
      assert_equal "one two\nthree\n", render("one\ntwo\nthree", width: 8)
    end

    it 'does not wrap when no width is known' do
      assert_equal "#{(['word'] * 30).join(' ')}\n", render('word ' * 30, width: nil)
    end

    it 'folds runs of spaces when no width is known' do
      assert_equal "a b\n", render('a    b', width: nil)
    end

    it 'collapses a run of blank lines to one' do
      assert_equal "a\n\nb\n", render("a\n\n\n\nb")
    end

    it 'drops leading and trailing blank lines' do
      assert_equal "a\n", render("\n\na\n\n")
    end

    it 'renders nothing for an empty source' do
      assert_empty render('')
    end

    it 'renders nothing for a blank source' do
      assert_empty render("\n\n  \n")
    end
  end

  describe 'headings' do
    it 'paints a heading and drops its marks in colour' do
      assert_equal "\e[1m\e[38;2;122;92;255mTitle\e[0m\e[0m\n", render('## Title', enabled: true)
    end

    it 'keeps the marks without colour' do
      assert_equal "## Title\n", render('## Title')
    end

    it 'drops a closing run of marks' do
      assert_equal "## Title\n", render('## Title ##')
    end
  end

  describe 'fenced code' do
    it 'labels the language above a gutter' do
      assert_equal "ruby\n│ puts 1\n", render("```ruby\nputs 1\n```")
    end

    it 'omits the label when the fence names no language' do
      assert_equal "│ puts 1\n", render("```\nputs 1\n```")
    end

    it 'keeps indentation and blank lines' do
      assert_equal "│ if x\n│\n│   y\n", render("```\nif x\n\n  y\n```")
    end

    it 'strips the indentation of the opening fence from the code' do
      assert_equal "│   x\n│ y\n", render("  ```\n    x\n  y\n  ```")
    end

    it 'runs an unclosed fence to the end of the source' do
      assert_equal "ruby\n│ puts 1\n│\n│ # still code\n", render("```ruby\nputs 1\n\n# still code")
    end

    it 'closes a tilde fence only on a fence at least as long' do
      assert_equal "py\n│ ```\n│ inner\n│ ```\n", render("~~~~py\n```\ninner\n```\n~~~~")
    end

    it 'cuts a long line at the width behind the gutter' do
      assert_equal "│ abcdef\n│ gh ij\n", render("```\nabcdefgh ij\n```", width: 8)
    end

    it 'does not cut a long line when no width is known' do
      assert_equal "│ #{'ab ' * 19}ab\n", render("```\n#{'ab ' * 20}\n```", width: nil)
    end

    it 'does not read markdown inside a fence' do
      assert_equal "│ # not **a** heading\n", render("```\n# not **a** heading\n```")
    end

    it 'paints the label, the gutter and the code' do
      assert_equal(
        "\e[2mruby\e[0m\n\e[2m│\e[0m \e[38;2;45;226;230mputs 1\e[0m\n",
        render("```ruby\nputs 1\n```", enabled: true)
      )
    end

    it 'leaves a blank code line unpainted' do
      assert_equal "\e[2m│\e[0m\n", render("```\na\n\nb\n```", enabled: true).lines.fetch(1)
    end
  end

  describe 'block quotes' do
    it 'renders a quote behind a gutter' do
      assert_equal "┃ a\n┃\n┃ b\n", render("> a\n>\n> b")
    end

    it 'paints the gutter' do
      assert_equal "\e[38;2;122;92;255m┃\e[0m a\n", render('> a', enabled: true)
    end

    it 'wraps a quote inside its gutter' do
      assert_equal "┃ one\n┃ two\n", render('> one two', width: 6)
    end

    it 'nests quotes' do
      assert_equal "┃ ┃ a\n┃ b\n", render(">> a\n> b")
    end

    it 'renders the blocks inside a quote' do
      assert_equal "┃ • a\n", render('> - a')
    end
  end

  describe 'lists' do
    it 'renders an unordered list with bullets' do
      assert_equal "• a\n• b\n", render("- a\n* b")
    end

    it 'paints the marker' do
      assert_equal "\e[38;2;192;76;253m•\e[0m a\n", render('- a', enabled: true)
    end

    it 'strips the indentation of an indented list' do
      assert_equal "• a\n• b\n", render("  - a\n  - b")
    end

    it 'keeps the numbers of an ordered list and aligns them' do
      assert_equal " 9. nine\n10. ten\n", render("9. nine\n10. ten")
    end

    it 'nests lists by indentation' do
      assert_equal "• a\n  • b\n    • c\n• d\n", render("- a\n  - b\n    - c\n- d")
    end

    it 'nests an unordered list under an ordered item' do
      assert_equal "1. a\n   • b\n2. c\n", render("1. a\n   - b\n2. c")
    end

    it 'wraps an item under its own text' do
      assert_equal "• one two\n  three\n", render('- one two three', width: 10)
    end

    it 'keeps a second paragraph inside its item' do
      assert_equal "• one\n\n  two\n• three\n", render("- one\n\n  two\n- three")
    end

    it 'renders a fence inside an item' do
      assert_equal "1. run\n   sh\n   │ ls\n", render("1. run\n   ```sh\n   ls\n   ```")
    end

    it 'renders an empty item as its marker' do
      assert_equal "•\n• x\n", render("-\n- x")
    end

    it 'renders an item whose marker is followed by more spaces than a regexp repeat allows' do
      assert_equal "• a b\n", render("-#{' ' * 100_001}a\n  b", width: nil)
    end
  end

  describe 'tables' do
    it 'prints a table whose header is past the column limit as text' do
      assert_equal "#{'|' * 33} |-| |a\n", render("#{'|' * 33}\n|-|\n|a", width: nil)
    end

    it 'prints a table with a body row past the column limit as text' do
      assert_equal "|h |-| #{'|' * 33}\n", render("|h\n|-|\n#{'|' * 33}", width: nil)
    end

    it 'renders a table with as many pipes as the limit as a grid' do
      assert_equal(
        "#{(['a'] * 33).join(' │ ')}\n#{(['─'] * 33).join('─┼─')}\n",
        render("#{(['a'] * 33).join('|')}\n|-|", width: nil)
      )
    end

    it 'renders a table as a grid' do
      assert_equal "a    │ b\n─────┼──\nlong │ 2\n", render("| a | b |\n|---|---|\n| long | 2 |")
    end

    it 'wraps a table to the width' do
      assert_equal "a │ b\n──┼──────────\nx │ one two\n  │ three\n",
                   render("| a | b |\n|---|---|\n| x | one two three |", width: 13)
    end
  end
end
