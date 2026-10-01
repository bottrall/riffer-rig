# frozen_string_literal: true

require 'test_helper'
require 'open3'

describe 'docs-site/check.rb' do
  root = File.expand_path('../..', __dir__)

  define_method(:check_copy) do |&edit|
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(%w[docs-site docs].map { |path| File.join(root, path) }, dir)
      FileUtils.mkdir_p(File.join(dir, 'lib', 'riffer', 'rig'))
      FileUtils.cp(File.join(root, 'lib', 'riffer', 'rig', 'version.rb'), File.join(dir, 'lib', 'riffer', 'rig'))
      edit&.call(dir)
      Open3.capture2e(RbConfig.ruby, 'docs-site/build.rb', chdir: dir)
      Open3.capture2e(RbConfig.ruby, 'docs-site/check.rb', chdir: dir)
    end
  end

  it 'passes on the current guides' do
    assert_predicate check_copy.last, :success?
  end

  it 'fails on a broken anchor' do
    broken_link = "\n[x](MCP.md#no-such-anchor)\n"
    output, = check_copy { |dir| File.write(File.join(dir, 'docs', 'TOOLS.md'), broken_link, mode: 'a') }

    assert_match %r{broken anchor /guides/mcp/#no-such-anchor}, output
  end
end
