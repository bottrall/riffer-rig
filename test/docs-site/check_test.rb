# frozen_string_literal: true

require 'test_helper'
require 'open3'

describe 'docs-site/check.rb' do
  root = File.expand_path('../..', __dir__)

  define_method(:check_site) do |pages|
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'docs-site'))
      FileUtils.cp(File.join(root, 'docs-site', 'check.rb'), File.join(dir, 'docs-site'))
      pages.each do |path, content|
        file = File.join(dir, '_site', path)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, content)
      end
      Open3.capture2e(RbConfig.ruby, 'docs-site/check.rb', chdir: dir)
    end
  end

  it 'aborts when the site has not been built' do
    output, = check_site({})

    assert_match %r{no built site at _site/}, output
  end

  it 'ignores pages under api/' do
    _, status = check_site('index.html' => '<p>ok</p>', 'api/index.html' => '<a href="/guides/missing/">x</a>')

    assert_predicate status, :success?
  end

  it 'ignores external links' do
    _, status = check_site('index.html' => '<a href="https://example.com/missing">x</a>')

    assert_predicate status, :success?
  end

  it 'ignores links into api/' do
    _, status = check_site('index.html' => '<a href="/api/index.html">x</a>')

    assert_predicate status, :success?
  end

  it 'fails on a broken link' do
    output, = check_site('index.html' => '<a href="/guides/missing/">x</a>')

    assert_match %r{broken link /guides/missing/}, output
  end

  it 'ignores an empty fragment' do
    _, status = check_site('index.html' => '<a href="/guides/b/#">x</a>', 'guides/b/index.html' => '<p>b</p>')

    assert_predicate status, :success?
  end

  it 'fails on a broken anchor' do
    output, = check_site(
      'index.html' => '<a href="/guides/b/#no-such-anchor">x</a>',
      'guides/b/index.html' => '<h2 id="section">Section</h2>'
    )

    assert_match %r{broken anchor /guides/b/#no-such-anchor}, output
  end

  it 'resolves an anchor on the same page' do
    _, status = check_site('index.html' => '<h2 id="top">Top</h2><a href="#top">x</a>')

    assert_predicate status, :success?
  end

  it 'resolves an anchor on another page' do
    _, status = check_site(
      'index.html' => '<a href="/guides/b/#section">x</a>',
      'guides/b/index.html' => '<h2 id="section">Section</h2>'
    )

    assert_predicate status, :success?
  end

  it 'resolves an anchor in a file that is not a page' do
    _, status = check_site(
      'index.html' => '<a href="/favicon.svg#dot">x</a>',
      'favicon.svg' => '<svg id="dot"></svg>'
    )

    assert_predicate status, :success?
  end

  it 'resolves relative links against the linking page' do
    _, status = check_site('guides/a/index.html' => '<a href="../b/">x</a>', 'guides/b/index.html' => '<p>b</p>')

    assert_predicate status, :success?
  end
end
