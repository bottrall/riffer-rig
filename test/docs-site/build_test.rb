# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'yaml'

describe 'docs-site/build.rb' do
  root = File.expand_path('../..', __dir__)
  built = nil

  define_method(:manifest_slugs) do
    YAML.load_file(File.join(root, 'docs-site', 'manifest.yml'))
        .fetch('groups')
        .flat_map { |group| group.fetch('pages') }
        .map { |page| page.fetch('slug') }
  end

  define_method(:build_copy) do |edit: nil, &read|
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(%w[docs-site docs].map { |path| File.join(root, path) }, dir)
      FileUtils.mkdir_p(File.join(dir, 'lib', 'riffer', 'rig'))
      FileUtils.cp(File.join(root, 'lib', 'riffer', 'rig', 'version.rb'), File.join(dir, 'lib', 'riffer', 'rig'))
      edit&.call(dir)
      output, status = Open3.capture2e(RbConfig.ruby, 'docs-site/build.rb', chdir: dir)
      read.call(dir, output, status)
    end
  end

  define_method(:site_files) do |dir|
    site = File.join(dir, '_site')
    Dir.glob('**/*', File::FNM_DOTMATCH, base: site)
       .select { |path| File.file?(File.join(site, path)) }
       .to_h { |path| [path, File.read(File.join(site, path))] }
  end

  define_method(:build) { built ||= build_copy { |dir, _output, status| [status, site_files(dir)] } }

  define_method(:guide_html) { |slug| build.last.fetch("guides/#{slug}/index.html") }

  define_method(:build_output) { |edit| build_copy(edit: edit) { |_dir, output, _status| output } }

  define_method(:append_to_tools) { |dir, text| File.write(File.join(dir, 'docs', 'TOOLS.md'), text, mode: 'a') }

  define_method(:built_with_tools_appended) do |text, path|
    build_copy(edit: ->(dir) { append_to_tools(dir, text) }) do |dir, _output, _status|
      File.read(File.join(dir, '_site', path))
    end
  end

  it 'exits successfully' do
    assert_predicate build.first, :success?
  end

  it 'copies the CNAME' do
    assert_equal "riffer.bottrall.dev\n", build.last['CNAME']
  end

  it 'copies the .nojekyll' do
    assert_equal '', build.last['.nojekyll']
  end

  it 'builds a page for every manifest entry' do
    assert_empty(manifest_slugs.reject { |slug| build.last.key?("guides/#{slug}/index.html") })
  end

  it 'declares the markdown twin of each page' do
    assert_includes guide_html('tools'), '<link rel="alternate" type="text/markdown" href="/guides/tools.md" />'
  end

  it 'gives the first guide no previous link' do
    refute_includes guide_html(manifest_slugs.first), 'class="doc" href='
  end

  it 'links each guide back to the one before it' do
    assert_includes guide_html(manifest_slugs[1]), %(class="doc" href="/guides/#{manifest_slugs.first}/")
  end

  it 'writes a markdown twin for every manifest entry' do
    assert_empty(manifest_slugs.reject { |slug| build.last.key?("guides/#{slug}.md") })
  end

  it 'keeps the title line in the markdown twin' do
    assert_equal "# Tools\n", build.last.fetch('guides/tools.md').lines.first
  end

  it 'aborts when a manifest entry has no source file' do
    output = build_output(->(dir) { File.delete(File.join(dir, 'docs', 'OVERVIEW.md')) })

    assert_includes output, 'manifest entry has no source file: docs/OVERVIEW.md'
  end

  it 'aborts when a guide is missing from the manifest' do
    output = build_output(->(dir) { File.write(File.join(dir, 'docs', 'NEW.md'), "# New\n") })

    assert_includes output, 'docs/NEW.md is missing from docs-site/manifest.yml'
  end

  it 'aborts when a guide links to a page that is not in the manifest' do
    output = build_output(->(dir) { append_to_tools(dir, "\n[x](NOPE.md)\n") })

    assert_includes output, 'docs/TOOLS.md links to unknown page: NOPE.md'
  end

  it 'rewrites a guide link to its page URL, keeping the fragment' do
    html = built_with_tools_appended("\n[x](MCP.md#secret-headers)\n", 'guides/tools/index.html')

    assert_includes html, 'href="/guides/mcp/#secret-headers"'
  end

  it 'rewrites a guide link in the markdown twin to its markdown URL, keeping the fragment' do
    markdown = built_with_tools_appended("\n[x](MCP.md#secret-headers)\n", 'guides/tools.md')

    assert_includes markdown, '[x](/guides/mcp.md#secret-headers)'
  end

  it 'leaves a guide link inside a fenced code block of the markdown twin as written' do
    markdown = built_with_tools_appended("\n```\n[x](MCP.md)\n```\n", 'guides/tools.md')

    assert_includes markdown, "```\n[x](MCP.md)\n```"
  end

  it 'leaves a guide link inside a code span of the markdown twin as written' do
    markdown = built_with_tools_appended("\n`[x](MCP.md)`\n", 'guides/tools.md')

    assert_includes markdown, '`[x](MCP.md)`'
  end
end
