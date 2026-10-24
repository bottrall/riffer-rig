# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Assembly do
  def assembly(extensions, settings: {}, allowlist: nil, strict: false)
    Riffer::Rig::Runtime::Assembly.new(extensions, settings, allowlist, strict: strict)
  end

  def extension(name, &)
    Riffer::Rig::Extension.new(name, &)
  end

  def replaced_bash
    Class.new(Riffer::Tool) do
      identifier 'bash'
      description 'A sandboxed shell'
    end
  end

  before do
    @read = extension('read') { |rig| rig.tool Riffer::Rig::Tools::Read }
    @bash = extension('bash') { |rig| rig.tool Riffer::Rig::Tools::Bash }
    @broken = extension('broken') do |rig|
      rig.tool Riffer::Rig::Tools::Write
      raise 'kaboom'
    end
  end

  it 'is frozen' do
    assert_predicate assembly([@read]), :frozen?
  end

  describe 'a raising extension' do
    it 'assembles the extensions around it' do
      assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], assembly([@read, @broken, @bash]).tools
    end

    it 'records it as a failure' do
      failures = assembly([@read, @broken, @bash]).failures

      assert_equal([[@broken, 'kaboom']], failures.map { |failure| [failure.extension, failure.error.message] })
    end

    it 'records no failures when every extension loads' do
      assert_empty assembly([@read, @bash]).failures
    end

    it 'raises its error when strict' do
      assert_raises(RuntimeError) { assembly([@read, @broken, @bash], strict: true) }
    end
  end

  describe '#tools' do
    it 'lets a later extension replace a tool by identifier' do
      sandbox = replaced_bash
      replacement = extension('sandbox') { |rig| rig.tool sandbox }

      assert_equal [Riffer::Rig::Tools::Read, sandbox], assembly([@read, @bash, replacement]).tools
    end

    it 'keeps only the allowlisted tools' do
      assert_equal [Riffer::Rig::Tools::Bash], assembly([@read, @bash], allowlist: %w[bash]).tools
    end
  end

  describe '#hooks' do
    it 'merges each event\'s hooks in extension order' do
      first = ->(_event) {}
      second = ->(_event) {}
      hooks = assembly(
        [extension('one') { |rig| rig.on(:turn_end, &first) },
         extension('two') { |rig| rig.on(:turn_end, &second) }]
      ).hooks

      assert_equal [first, second], hooks.fetch(:turn_end)
    end

    it 'holds an empty list for an event no extension hooks' do
      assert_empty assembly([@read]).hooks.fetch(:stream)
    end
  end

  describe '#mcp_declarations' do
    it 'collects the servers every extension declared' do
      serving = extension('serving') { |rig| rig.mcp('docs', url: 'https://docs.test/mcp') }

      assert_equal %w[docs], assembly([serving]).mcp_declarations.keys
    end
  end

  describe '#prompt_sections' do
    it 'lets a later registration of the same section name win' do
      earlier = extension('earlier') { |rig| rig.prompt(:branch) { 'EARLIER' } }
      later = extension('later') { |rig| rig.prompt(:branch) { 'LATER' } }

      assert_equal 'LATER', assembly([earlier, later]).prompt_sections.fetch(:branch).call(nil)
    end
  end

  describe 'declared settings' do
    before do
      @git = extension('git') do |rig|
        rig.setting :depth, default: 3
        rig.setting :remote, default: 'origin'
      end
    end

    it 'lists the declared keys per extension' do
      bare = extension('bare') { |rig| rig.tool Riffer::Rig::Tools::Read }

      assert_equal({ git: { depth: 3, remote: 'origin' } }, assembly([@git, bare]).declared_settings)
    end

    it 'applies a declared default when the settings lack the key' do
      assert_equal({ git: { depth: 3, remote: 'origin' } }, assembly([@git]).settings)
    end

    it 'lets a provided value override the declared default' do
      settings = assembly([@git], settings: { model: 'mock/other', git: { depth: 10 } }).settings

      assert_equal({ model: 'mock/other', git: { depth: 10, remote: 'origin' } }, settings)
    end
  end

  describe '#overrides' do
    it 'reports a replaced tool' do
      sandbox = replaced_bash
      replacement = extension('sandbox') { |rig| rig.tool sandbox }

      assert_equal ['Extension sandbox replaces tool bash from bash'], assembly([@bash, replacement]).overrides
    end

    it 'reports a replaced command' do
      earlier = extension('earlier') { |rig| rig.command('log', description: 'a') { |_ctx| nil } }
      later = extension('later') { |rig| rig.command('log', description: 'b') { |_ctx| nil } }

      assert_equal ['Extension later replaces command log from earlier'], assembly([earlier, later]).overrides
    end

    it 'reports a replaced prompt section' do
      earlier = extension('earlier') { |rig| rig.prompt(:branch) { 'a' } }
      later = extension('later') { |rig| rig.prompt(:branch) { 'b' } }

      assert_equal ['Extension later replaces prompt section branch from earlier'], assembly([earlier, later]).overrides
    end

    it 'reports nothing when no registration is replaced' do
      assert_empty assembly(Riffer::Rig.bundled).overrides
    end
  end

  describe '#unknown_tools' do
    it 'reports nothing without an allowlist' do
      assert_empty assembly([@read]).unknown_tools
    end

    it 'reports nothing when every allowlisted name is a registered tool' do
      assert_empty assembly([@read, @bash], allowlist: %w[read bash]).unknown_tools
    end

    it 'reports each allowlisted name no extension registered' do
      unknown = assembly([@read, @bash], allowlist: %w[raed bash nope]).unknown_tools

      assert_equal ['Unknown tool in allowlist: raed', 'Unknown tool in allowlist: nope'], unknown
    end
  end

  describe '#skills_config' do
    it 'is nil without a skill source' do
      assert_nil assembly([@read]).skills_config(Riffer::Rig::Runtime.new('mock/test'))
    end

    it 'hands the runtime to each skill source' do
      seen = []
      skilled = extension('skilled') do |rig|
        rig.skills do |runtime|
          seen << runtime
          Riffer::Skills::FilesystemBackend.new(Dir.pwd)
        end
      end
      runtime = Riffer::Rig::Runtime.new('mock/test')
      assembly([skilled]).skills_config(runtime)

      assert_equal [runtime], seen
    end
  end

  describe '#commands' do
    def command(name)
      Riffer::Rig::Command.new(name, description: name, extension: :core) { |_ctx| nil }
    end

    it 'lists the given core commands, the built-in ones, then the extensions\'' do
      logging = extension('logging') { |rig| rig.command('log', description: 'Log') { |_ctx| nil } }

      assert_equal %w[reload auth model reasoning cost log], assembly([logging]).commands([command('reload')], []).keys
    end

    it 'adds a command for each skill' do
      skill = Riffer::Skills::Frontmatter.new(name: 'a', description: 'A.')

      assert_includes assembly([]).commands([], [skill]).keys, 'skill:a'
    end

    it 'lets an extension command replace a core one of the same name' do
      replacing = extension('replacing') { |rig| rig.command('reload', description: 'Mine') { |_ctx| nil } }

      assert_equal 'Mine', assembly([replacing]).commands([command('reload')], []).fetch('reload').description
    end
  end
end
