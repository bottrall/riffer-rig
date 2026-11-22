#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'yaml'

require 'kramdown'
require 'kramdown-parser-gfm'
require 'rouge'

require_relative '../lib/riffer/rig/version'

HERE = Pathname(__dir__)
ROOT = HERE.parent
DOCS = ROOT.join('docs')
SITE = ROOT.join('_site')

# GitHub Pages runs a site through Jekyll unless it has a .nojekyll, and Jekyll
# would turn each guide's markdown twin into HTML instead of serving it as is.
ASSETS = %w[site.css landing.css copy.js favicon.svg 404.html CNAME .nojekyll].freeze

# Code is matched first so that a link-shaped example inside it is left as written.
MARKDOWN_LINK = /
  (?<code>^[ \t]*(?<fence>`{3,}|~{3,}).*?^[ \t]*\k<fence>|(?<ticks>`+).+?\k<ticks>)
  |\]\((?<path>[^)\s:\#]+\.md)(?<fragment>\#[^)\s]*)?\)
/mx

VERSION = Riffer::Rig::VERSION

Page = Data.define(:source, :slug, :title, :num, :description, :featured, :group_label) do
  def url = "/guides/#{slug}/"
  def markdown_url = "/guides/#{slug}.md"
end

Group = Data.define(:label, :tone, :pages)

def main
  manifest = YAML.safe_load_file(HERE.join('manifest.yml'), symbolize_names: true).fetch(:groups)
  validate_manifest!(manifest)

  groups = build_groups(manifest)
  pages = groups.flat_map(&:pages)
  pages_by_source = pages.to_h { |page| [page.source, page] }

  layout = ERB.new(HERE.join('layout.html.erb').read, trim_mode: '-')
  landing = ERB.new(HERE.join('index.html.erb').read, trim_mode: '-')

  FileUtils.rm_rf(SITE.join('guides'))
  FileUtils.mkdir_p(SITE)
  ASSETS.each { |asset| FileUtils.cp(HERE.join(asset), SITE) }

  SITE.join('index.html').write(landing.result_with_hash(groups: groups, pages: pages, version: VERSION))

  pages.each_with_index do |page, index|
    markdown = DOCS.join(page.source).read
    body = render_body(markdown, page.source, pages_by_source)
    html = layout.result_with_hash(
      page: page,
      groups: groups,
      pages: pages,
      body: body,
      toc: extract_toc(body),
      prev_page: index.positive? ? pages[index - 1] : nil,
      next_page: pages[index + 1],
      version: VERSION
    )
    dir = SITE.join('guides', page.slug)
    FileUtils.mkdir_p(dir)
    dir.join('index.html').write(html)
    SITE.join('guides', "#{page.slug}.md").write(rewrite_markdown_links(markdown, page.source, pages_by_source))
  end

  puts "Built landing + #{pages.size} guide pages (HTML and markdown) + 404 into #{SITE.relative_path_from(ROOT)}/"
end

def validate_manifest!(manifest)
  sources = manifest.flat_map { |group| group[:pages] }.map { |entry| entry[:source] }
  missing = sources.reject { |source| DOCS.join(source).file? }
  on_disk = Pathname.glob(DOCS.join('**/*.md')).map { |path| path.relative_path_from(DOCS).to_s }
  unlisted = on_disk - sources

  errors = missing.map { |source| "manifest entry has no source file: docs/#{source}" } +
           unlisted.map { |source| "docs/#{source} is missing from docs-site/manifest.yml" }
  abort errors.join("\n") unless errors.empty?
end

def build_groups(manifest)
  numbers = chapter_numbers(manifest)
  manifest.map do |group|
    Group.new(
      label: group[:label],
      tone: group[:tone],
      pages: group[:pages].map { |entry| build_page(entry, group[:label], numbers.fetch(entry[:source])) }
    )
  end
end

def chapter_numbers(manifest)
  manifest
    .flat_map { |group| group[:pages] }
    .map { |entry| entry[:source] }
    .group_by { |source| File.dirname(source) }
    .values
    .flat_map { |sources| sources.each_with_index.map { |source, index| [source, format('%02d', index + 1)] } }
    .to_h
end

def build_page(entry, label, num)
  source = DOCS.join(entry[:source]).read
  Page.new(
    source: entry[:source],
    slug: entry[:slug],
    title: source[/^# (.+)$/, 1],
    num: num,
    description: entry[:description],
    featured: entry.fetch(:featured, false),
    group_label: label
  )
end

def render_body(markdown, source, pages_by_source)
  untitled = markdown.sub(/^# .+\n/, '')
  html = Kramdown::Document.new(untitled, input: 'GFM', syntax_highlighter: :rouge, hard_wrap: false).to_html
  rewrite_links(html, source, pages_by_source)
end

def rewrite_links(html, source, pages_by_source)
  html.gsub(/href="(?<path>[^":]+\.md)(?<fragment>#[^"]*)?"/) do
    match = Regexp.last_match
    %(href="#{linked_page(source, match[:path], pages_by_source).url}#{match[:fragment]}")
  end
end

def rewrite_markdown_links(markdown, source, pages_by_source)
  markdown.gsub(MARKDOWN_LINK) do
    match = Regexp.last_match
    next match[:code] if match[:code]

    "](#{linked_page(source, match[:path], pages_by_source).markdown_url}#{match[:fragment]})"
  end
end

def linked_page(source, path, pages_by_source)
  target = Pathname(source).dirname.join(path).cleanpath.to_s
  pages_by_source.fetch(target) { abort "docs/#{source} links to unknown page: #{path}" }
end

def extract_toc(body)
  body.scan(%r{<h2 id="([^"]+)"[^>]*>(.*?)</h2>}m).map do |id, text|
    { id: id, title: text.gsub(/<[^>]+>/, '') }
  end
end

main
