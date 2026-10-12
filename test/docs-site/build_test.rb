# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'yaml'

describe 'bin/docs' do
  root = File.expand_path('../..', __dir__)
  site = File.join(root, '_site')

  define_singleton_method(:build) { @build ||= Open3.capture2e('bin/docs', chdir: root) }

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

  define_method(:build_output) { |edit| build_copy(edit: edit) { |_dir, output, _status| output } }

  define_method(:append_to_tools) { |dir, text| File.write(File.join(dir, 'docs', 'TOOLS.md'), text, mode: 'a') }

  before { self.class.build }

  it 'exits successfully' do
    assert_predicate self.class.build.last, :success?
  end

  it 'builds a page for every manifest entry' do
    assert_empty(manifest_slugs.reject { |slug| File.file?(File.join(site, 'guides', slug, 'index.html')) })
  end

  it 'copies the CNAME' do
    assert_equal "riffer.bottrall.dev\n", File.read(File.join(site, 'CNAME'))
  end

  it 'gives the first guide no previous link' do
    html = File.read(File.join(site, 'guides', manifest_slugs.first, 'index.html'))

    refute_includes html, 'class="doc" href='
  end

  it 'links each guide back to the one before it' do
    html = File.read(File.join(site, 'guides', manifest_slugs[1], 'index.html'))

    assert_includes html, %(class="doc" href="/guides/#{manifest_slugs.first}/")
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
    edit = ->(dir) { append_to_tools(dir, "\n[x](MCP.md#secret-headers)\n") }
    html = build_copy(edit: edit) do |dir, _output, _status|
      File.read(File.join(dir, '_site', 'guides', 'tools', 'index.html'))
    end

    assert_includes html, 'href="/guides/mcp/#secret-headers"'
  end
end
