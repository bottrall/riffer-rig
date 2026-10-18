# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'yaml'

describe 'docs-site/check.rb' do
  root = File.expand_path('../..', __dir__)

  define_method(:check_site) do |pages|
    run_check(pages, "# Readme\n", {}, [])
  end

  define_method(:check_readme) do |readme, pages: { 'index.html' => '<p>ok</p>' }, files: {}, guides: []|
    run_check(pages, readme, files, guides)
  end

  define_method(:run_check) do |pages, readme, files, guides|
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'docs-site'))
      FileUtils.cp(File.join(root, 'docs-site', 'check.rb'), File.join(dir, 'docs-site'))
      File.write(File.join(dir, 'docs-site', 'manifest.yml'), { 'groups' => [{ 'pages' => guides }] }.to_yaml)
      site_files = pages.to_h { |path, content| [File.join('_site', path), content] }
      site_files.merge(files, 'README.md' => readme).each do |path, content|
        file = File.join(dir, path)
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

  describe 'the README' do
    it 'ignores external links' do
      _, status = check_readme("[x](https://example.com/missing)\n")

      assert_predicate status, :success?
    end

    it 'resolves an anchor on the README itself' do
      _, status = check_readme("## Install\n\n[x](#install)\n")

      assert_predicate status, :success?
    end

    it 'fails on an anchor missing from the README itself' do
      output, = check_readme("[x](#nowhere)\n")

      assert_match(/README.md: broken anchor #nowhere/, output)
    end

    it 'fails on a link to a missing file' do
      output, = check_readme("[x](docs/MISSING.md)\n")

      assert_match %r{README.md: broken link docs/MISSING.md}, output
    end

    it 'resolves a link to a file without a fragment' do
      _, status = check_readme("[x](LICENSE.txt)\n", files: { 'LICENSE.txt' => 'MIT' })

      assert_predicate status, :success?
    end

    it 'fails on an anchor into a file that is not a guide' do
      output, = check_readme(
        "[x](CHANGELOG.md#v1)\n", files: { 'CHANGELOG.md' => '# Changelog' }
      )

      assert_match(/README.md: anchor into a file that is not a guide CHANGELOG.md#v1/, output)
    end

    it 'resolves an anchor into a guide through the manifest' do
      _, status = check_readme(
        "[x](docs/A.md#section)\n",
        pages: { 'guides/a/index.html' => '<h2 id="section">Section</h2>' },
        files: { 'docs/A.md' => '# A' },
        guides: [{ 'source' => 'A.md', 'slug' => 'a' }]
      )

      assert_predicate status, :success?
    end

    it 'fails on an anchor missing from its guide' do
      output, = check_readme(
        "[x](docs/A.md#nowhere)\n",
        pages: { 'guides/a/index.html' => '<h2 id="section">Section</h2>' },
        files: { 'docs/A.md' => '# A' },
        guides: [{ 'source' => 'A.md', 'slug' => 'a' }]
      )

      assert_match %r{README.md: broken anchor docs/A.md#nowhere}, output
    end
  end
end
