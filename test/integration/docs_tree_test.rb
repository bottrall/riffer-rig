# frozen_string_literal: true

require 'test_helper'
require 'open3'

describe 'the deployable docs tree' do
  root = File.expand_path('../..', __dir__)
  site = File.join(root, '_site')

  define_singleton_method(:build) { @build ||= Open3.capture2e('bin/docs', chdir: root) }

  before { self.class.build }

  it 'builds the API reference at /api/ alongside the site' do
    assert_path_exists File.join(site, 'api', 'index.html')
  end
end
