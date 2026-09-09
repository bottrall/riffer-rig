# frozen_string_literal: true

# Every project chore is defined here, once. The scripts in bin/ are the
# documented entry points; each one delegates to a task below and adds nothing
# but argument translation. See README "Development".

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rubocop/rake_task'
require 'tmpdir'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

# Extra CLI arguments arrive via RUBOCOP_OPTS, mirroring rake's TESTOPTS.
RuboCop::RakeTask.new do |t|
  t.options = ENV.fetch('RUBOCOP_OPTS', '').split
end

namespace :rbs do
  desc 'Generate RBS signatures from inline annotations'
  task :generate do
    sh 'rbs-inline --opt-out --output=sig/generated lib'
  end

  desc 'Fail if sig/generated is out of date with lib/'
  task :check do
    Dir.mktmpdir('rbs-check') do |dir|
      sh "rbs-inline --opt-out --output=#{dir} lib", verbose: false
      sh "diff -ru sig/generated #{dir}" do |ok, _|
        abort 'sig/generated is out of date; run bin/rbs and commit the result' unless ok
      end
    end
  end

  desc 'Fail if a .rbs file in sig/manual or sig/_private shadows a deleted module'
  task :lint_manual do
    stale = Dir['sig/manual/**/*.rbs', 'sig/_private/riffer/**/*.rbs'].filter_map do |file|
      module_name = File.readlines(file).lazy
                        .filter_map { |line| line[/^module ([A-Z][\w:]*)/, 1] }
                        .first
      file if module_name && !File.exist?("lib/#{module_name.split('::').map(&:downcase).join('/')}.rb")
    end
    abort "sig files shadow deleted modules: #{stale.join(', ')}" unless stale.empty?
  end

  desc 'Watch lib/ for changes and regenerate RBS files'
  task :watch do
    require 'guard'
    require 'guard/commander'

    Guard.start(no_interactions: true)
  end
end

namespace :steep do
  desc 'Type-check with Steep'
  task :check do
    sh "steep check #{ENV.fetch('STEEP_OPTS', '')}".strip
  end
end

desc 'Serve the building plans in plans/ at http://localhost:8001'
task :plans do
  ruby '-run -e httpd plans -p 8001'
end

desc 'Check RBS signatures are current, then type-check'
task typecheck: %w[rbs:check rbs:lint_manual steep:check]

desc 'Run everything CI runs'
task ci: %i[test rubocop typecheck]

task default: :ci
