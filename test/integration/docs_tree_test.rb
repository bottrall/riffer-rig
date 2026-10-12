# frozen_string_literal: true

require 'test_helper'
require 'open3'

describe 'the deployable docs tree' do
  root = File.expand_path('../..', __dir__)
  sources = %w[bin docs docs-site lib Rakefile Gemfile Gemfile.lock riffer-rig.gemspec README.md CHANGELOG.md
               LICENSE.txt]

  # Built in a copy: the checkout's _site/ is gitignored and survives between runs, so a stale tree would pass.
  define_singleton_method(:build) do
    @build ||= Dir.mktmpdir do |dir|
      FileUtils.cp_r(sources.map { |path| File.join(root, path) }, dir)
      _, built = Open3.capture2e('bin/docs', chdir: dir)
      _, checked = Open3.capture2e(RbConfig.ruby, 'docs-site/check.rb', chdir: dir)
      { built: built, checked: checked, api: File.exist?(File.join(dir, '_site', 'api', 'index.html')) }
    end
  end

  it 'builds with bin/docs' do
    assert_predicate self.class.build.fetch(:built), :success?
  end

  it 'builds the API reference at /api/ alongside the site' do
    assert self.class.build.fetch(:api)
  end

  it 'passes the link check on the current guides' do
    assert_predicate self.class.build.fetch(:checked), :success?
  end
end
