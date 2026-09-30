# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'yaml'

describe 'bin/docs' do
  root = File.expand_path('../..', __dir__)
  site = File.join(root, '_site')

  define_singleton_method(:build) { @build ||= Open3.capture2e('bin/docs', chdir: root) }

  before { self.class.build }

  it 'exits successfully' do
    assert_predicate self.class.build.last, :success?
  end

  it 'builds a page for every manifest entry' do
    slugs = YAML.load_file(File.join(root, 'docs-site', 'manifest.yml'))
                .fetch('groups')
                .flat_map { |group| group.fetch('pages') }
                .map { |page| page.fetch('slug') }

    assert_empty(slugs.reject { |slug| File.file?(File.join(site, 'guides', slug, 'index.html')) })
  end

  it 'builds the API reference at /api/' do
    assert_path_exists File.join(site, 'api', 'index.html')
  end

  it 'copies the CNAME' do
    assert_equal "riffer.bottrall.dev\n", File.read(File.join(site, 'CNAME'))
  end
end
