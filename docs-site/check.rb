#!/usr/bin/env ruby
# frozen_string_literal: true

require 'kramdown'
require 'kramdown-parser-gfm'
require 'yaml'

ROOT = Pathname(__dir__).join('..').expand_path
SITE = ROOT.join('_site')

EXTERNAL = %r{\A(?:https?:|mailto:|//)}

def main
  pages = site_pages
  abort 'docs:check: no built site at _site/ — run `rake docs:site` first' if pages.empty?

  id_index = pages.to_h { |file| [file, ids(file.read)] }
  errors = pages.flat_map { |file| page_errors(file, id_index) } + readme_errors(id_index)

  if errors.empty?
    puts "docs:check passed: #{pages.size} pages and the README, all internal links and anchors resolve"
  else
    errors.each { |error| warn error }
    abort "docs:check failed: #{errors.size} broken link(s)"
  end
end

def site_pages
  Pathname.glob(SITE.join('**/*.html')).reject do |file|
    file.relative_path_from(SITE).to_s.start_with?('api/')
  end
end

def ids(html)
  html.scan(/\bid="([^"]+)"/).flatten
end

def page_errors(file, id_index)
  links(file.read)
    .grep_v(EXTERNAL)
    # RDoc builds /api/ in a separate task, so it is absent when only the site has been built.
    .reject { |link| link.start_with?('/api/') }
    .filter_map { |link| link_error(file, link, id_index) }
end

def links(html)
  html.scan(/\b(?:href|src)="([^"]+)"/).flatten
end

def link_error(file, link, id_index)
  path, fragment = link.split('#', 2)
  target = path.empty? ? file : resolve(file, path)
  return "#{file.relative_path_from(SITE)}: broken link #{link}" unless target.file?
  return nil if fragment.nil? || fragment.empty?

  anchor_ids = id_index.fetch(target) { ids(target.read) }
  "#{file.relative_path_from(SITE)}: broken anchor #{link}" unless anchor_ids.include?(fragment)
end

# The README is not a site page, so its links are checked against the repo for
# paths and against the built guide page a docs/ source maps to for anchors.
def readme_errors(id_index)
  html = Kramdown::Document.new(ROOT.join('README.md').read, input: 'GFM', syntax_highlighter: nil).to_html
  guide_pages = guide_pages_by_source
  links(html).grep_v(EXTERNAL).filter_map { |link| readme_link_error(link, ids(html), guide_pages, id_index) }
end

def guide_pages_by_source
  YAML.safe_load_file(ROOT.join('docs-site/manifest.yml'), symbolize_names: true)
      .fetch(:groups)
      .flat_map { |group| group[:pages] }
      .to_h { |page| ["docs/#{page[:source]}", SITE.join('guides', page[:slug], 'index.html')] }
end

def readme_link_error(link, readme_ids, guide_pages, id_index)
  path, fragment = link.split('#', 2)
  return readme_anchor_error(link, readme_ids.include?(fragment)) if path.empty?
  return "README.md: broken link #{link}" unless ROOT.join(path).exist?
  return nil if fragment.nil? || fragment.empty?

  page = guide_pages[path]
  return "README.md: anchor into a file that is not a guide #{link}" unless page

  readme_anchor_error(link, id_index.fetch(page, []).include?(fragment))
end

def readme_anchor_error(link, found)
  "README.md: broken anchor #{link}" unless found
end

def resolve(file, path)
  target = path.start_with?('/') ? SITE.join(path.delete_prefix('/')) : file.dirname.join(path)
  target.directory? ? target.join('index.html') : target
end

main
