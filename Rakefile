# frozen_string_literal: true

require 'fileutils'
require 'rake/testtask'
require 'rbconfig'
require 'rubocop/rake_task'
require 'tmpdir'

GEMSPEC = 'riffer-rig.gemspec'

# bin/test passes TEST as a comma-separated list of files and globs, and
# Rake::TestTask would read it as one glob, so it's taken out of ENV and split.
requested_tests = ENV.delete('TEST')&.split(',')

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList[*(requested_tests || 'test/**/*_test.rb')]
  t.warning = false
end

RuboCop::RakeTask.new(:lint) do |t|
  # RuboCop also applies AllCops/Exclude from every .rubocop.yml above the
  # project, so a checkout inside another one (a worktree under .claude/)
  # would otherwise inspect nothing and pass.
  t.options = ['--ignore-parent-exclusion', *ENV.fetch('RUBOCOP_OPTS', '').split]
end

desc 'Install the gem signatures rbs_collection.lock.yaml locks, writing the lockfile if there is none'
task :setup do
  sh 'rbs collection install'
end

# Starting empty drops a deleted file's signatures.
def write_signatures(output)
  FileUtils.rm_rf(output)
  FileUtils.mkdir_p(output)
  sh 'rbs-inline', '--opt-out', "--output=#{output}", 'lib', verbose: false
end

desc 'Regenerate sig/generated from the inline annotations in lib/'
task :generate do
  write_signatures('sig/generated')
end

namespace :generate do
  desc 'Regenerate sig/generated whenever a file in lib/ changes'
  task :watch do
    require 'guard'
    require 'guard/commander'

    Guard.start(no_interactions: true)
  end
end

namespace :rbs do
  desc 'Fail if sig/generated is out of date with lib/'
  task :check do
    FileUtils.mkdir_p(%w[tmp sig/generated])
    Dir.mktmpdir('rbs-check', 'tmp') do |dir|
      write_signatures(dir)
      sh 'diff', '-ru', 'sig/generated', dir do |ok, _|
        abort 'sig/generated is out of date; run bin/generate and commit the result' unless ok
      end
    end
  end

  desc 'Fail if rbs_collection.lock.yaml is out of date with rbs_collection.yaml or Gemfile.lock'
  task :collection_check do
    before = File.read('rbs_collection.lock.yaml')
    sh 'rbs collection update', verbose: false
    next if File.read('rbs_collection.lock.yaml') == before

    File.write('rbs_collection.lock.yaml', before)
    abort 'rbs_collection.lock.yaml is out of date; run `bundle exec rbs collection update` and commit the result'
  end

  desc 'Fail if a sig/manual file has no lib/ counterpart (a file or a Zeitwerk namespace directory)'
  task :lint_manual do
    stale = Dir['sig/manual/**/*.rbs'].reject do |file|
      lib_path = file.sub('sig/manual/', 'lib/').delete_suffix('.rbs')
      File.exist?("#{lib_path}.rb") || Dir.exist?(lib_path)
    end
    abort "sig/manual files without a lib/ counterpart: #{stale.join(', ')}" unless stale.empty?
  end
end

namespace :steep do
  desc 'Type-check lib/ with Steep'
  task :check do
    # --no-daemon: Steep otherwise routes the check through whatever language
    # server holds the project socket, including orphaned ones, which can hang
    # or report stale results.
    sh "steep check --no-daemon #{ENV.fetch('STEEP_OPTS', '')}".strip
  end
end

desc 'Check the signatures and the RBS collection are current, then type-check'
task typecheck: %w[rbs:check rbs:collection_check rbs:lint_manual steep:check]

namespace :docs do
  desc 'Build the docs site (landing, guides, 404, assets) into _site/'
  task :site do
    ruby 'docs-site/build.rb'
  end

  desc 'Build the full docs tree and validate all internal links and anchors'
  task check: :site do
    ruby 'docs-site/check.rb'
  end

  desc 'Build the docs site and serve it at http://localhost:8000'
  task serve: :site do
    ruby '-run -e httpd _site -p 8000'
  end
end

desc 'Build the full deployable docs tree into _site/'
task docs: 'docs:site'

namespace :gemspec do
  desc 'Fail if the gemspec depends on a provider SDK at runtime'
  task :check do
    sdks = Gem::Specification.load(GEMSPEC).runtime_dependencies.map(&:name) &
           %w[anthropic openai aws-sdk-bedrockruntime]
    abort "#{GEMSPEC} depends on a provider SDK: #{sdks.join(', ')}" unless sdks.empty?
  end
end

desc 'Build the gem into pkg/, then install it into an empty GEM_HOME and check it loads'
task build: 'gemspec:check' do
  spec = Gem::Specification.load(GEMSPEC)
  missing = Dir['lib/**/*.rb', 'sig/**/*.rbs'] - spec.files
  abort "#{GEMSPEC} leaves out #{missing.join(', ')}" unless missing.empty?

  gem_file = File.join('pkg', spec.file_name)
  FileUtils.mkdir_p(%w[pkg tmp])
  sh 'gem', 'build', GEMSPEC, '--output', gem_file

  Dir.mktmpdir('install', 'tmp') do |dir|
    gem_home = File.expand_path(dir)
    # The empty GEM_HOME receives only the built gem; its dependencies resolve
    # from the bundle's gem path, so --local never reaches the network.
    env = { 'GEM_HOME' => gem_home, 'GEM_PATH' => [gem_home, *Gem.path].join(File::PATH_SEPARATOR) }
    # Eager loading fails on a file that needs one the gem doesn't ship.
    check = <<~RUBY
      require 'riffer/rig'
      spec = Gem.loaded_specs.fetch('riffer-rig')
      abort "loaded \#{spec.full_gem_path}, not the built gem" unless spec.full_gem_path.start_with?(ENV['GEM_HOME'])
      Zeitwerk::Loader.eager_load_all
      puts "loaded riffer-rig \#{Riffer::Rig::VERSION} from the built gem"
    RUBY
    Bundler.with_unbundled_env do
      sh env, 'gem', 'install', '--local', '--no-document', gem_file
      sh env, RbConfig.ruby, '-e', check, verbose: false
    end
  end
end
