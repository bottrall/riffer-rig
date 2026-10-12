# frozen_string_literal: true

require 'test_helper'
require 'json'
require_relative '../../../support/confirming_host'
require_relative '../../../support/rig_files'

describe Riffer::Rig::Loader::ExtensionSource do
  include RigFiles

  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @host = ConfirmingHost.new([true])
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def source(host: @host)
    Riffer::Rig::Loader::ExtensionSource.new(cwd: @cwd, home: @home, host: host)
  end

  def recording(name)
    "Riffer::Rig.extension(#{name.inspect}) { |rig| }\n"
  end

  def appending(marker)
    "File.write(#{marker.inspect}, 'x', mode: 'a')\n"
  end

  def write_local(name, body)
    FileUtils.mkdir_p(File.join(@cwd, '.riffer'))
    path = File.expand_path(File.join(@cwd, '.riffer', "#{name}.rb"))
    File.write(path, body)
    path
  end

  def write_gem_file(body)
    dir = File.join(@cwd, 'gems', 'fixture')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'extension.rb'), body)
    File.expand_path(File.join(dir, 'extension.rb'))
  end

  def trust_file
    File.join(@home, '.riffer', 'trust.json')
  end

  def home_rig_path
    File.expand_path(File.join(@home, '.riffer', 'rig.rb'))
  end

  def marker
    File.join(@cwd, 'marker')
  end

  describe '#discover' do
    it 'tracks the files of the latest discovery alone' do
      write_rig(:home, '')
      discovered = source
      discovered.discover(autoload: false)
      FileUtils.rm(home_rig_path)
      discovered.discover(autoload: false)

      assert_empty discovered.tracked_files
    end

    describe 'autoload' do
      it 'leaves the gems alone without autoload' do
        gem_file = write_gem_file(recording('es_gem'))

        assert_empty(with_gem_files([gem_file]) { source.discover(autoload: false) })
      end

      it 'returns the gem extensions before the rig.rb ones' do
        gem_file = write_gem_file(recording('es_gem'))
        write_rig(:home, recording('es_home'))
        names = with_gem_files([gem_file]) { source.discover(autoload: true).map(&:name) }

        assert_equal %w[es_gem es_home], names
      end

      it 'leaves the gem files untracked' do
        gem_file = write_gem_file(recording('es_gem'))
        discovered = source
        with_gem_files([gem_file]) { discovered.discover(autoload: true) }

        assert_empty discovered.tracked_files
      end

      it 'reports a raising gem file through notify' do
        gem_file = write_gem_file('raise "boom"')
        with_gem_files([gem_file]) { source.discover(autoload: true) }

        assert_equal [[:error, "#{gem_file} failed to load: boom"]], @host.notifications
      end
    end

    it 'returns nothing without a rig.rb' do
      assert_empty source.discover(autoload: false)
    end

    describe 'trust' do
      it 'asks to confirm a project file the first time it is seen' do
        write_rig(:project, '')
        source.discover(autoload: false)

        assert_equal ["Trust #{project_rig_path}?"], @host.questions
      end

      it 'stores the answer by absolute path' do
        write_rig(:project, '')
        source.discover(autoload: false)

        assert_equal({ project_rig_path => true }, JSON.parse(File.read(trust_file)))
      end

      it 'does not ask again once an answer is stored' do
        write_rig(:project, '')
        source.discover(autoload: false)
        second = ConfirmingHost.new([true])
        source(host: second).discover(autoload: false)

        assert_empty second.questions
      end

      it 'skips a declined project file and its extensions' do
        write_rig(:project, recording('es_declined'))

        assert_empty source(host: ConfirmingHost.new([false])).discover(autoload: false)
      end

      it 'does not re-ask a declined file' do
        write_rig(:project, '')
        host = ConfirmingHost.new([false, true])
        source(host: host).discover(autoload: false)
        source(host: host).discover(autoload: false)

        assert_equal 1, host.questions.size
      end

      it 'reports nothing to the host for a declined file' do
        write_rig(:project, '')
        host = ConfirmingHost.new([false])
        source(host: host).discover(autoload: false)

        assert_empty host.notifications
      end

      it 'leaves a declined file untracked' do
        write_rig(:project, '')
        declined = source(host: ConfirmingHost.new([false]))
        declined.discover(autoload: false)

        assert_empty declined.tracked_files
      end

      it 'never asks about the home file' do
        write_rig(:home, '')
        source.discover(autoload: false)

        assert_empty @host.questions
      end

      it 'skips the project file for a host that cannot confirm' do
        write_rig(:project, recording('es_unconfirmed'))

        assert_empty source(host: Riffer::Rig::Hosts::Null.new).discover(autoload: false)
      end

      it 'does not record a decline from a host that cannot confirm' do
        write_rig(:project, '')
        source(host: Riffer::Rig::Hosts::Null.new).discover(autoload: false)

        refute_path_exists trust_file
      end
    end

    it 'returns the home extensions before the project ones' do
      write_rig(:home, recording('es_home'))
      write_rig(:project, recording('es_project'))

      assert_equal %w[es_home es_project], source.discover(autoload: false).map(&:name)
    end

    it 'tracks the home file before the project file' do
      write_rig(:home, '')
      write_rig(:project, '')
      discovered = source
      discovered.discover(autoload: false)

      assert_equal [home_rig_path, project_rig_path], discovered.tracked_files
    end

    it 'tracks a require_relative from rig.rb' do
      local = write_local('local', recording('es_local'))
      write_rig(:project, "require_relative 'local'")
      discovered = source
      discovered.discover(autoload: false)

      assert_equal [local, project_rig_path], discovered.tracked_files
    end

    it 'leaves required gem paths untracked' do
      write_rig(:project, "require 'json'")
      discovered = source
      discovered.discover(autoload: false)

      assert_equal [project_rig_path], discovered.tracked_files
    end

    it 'reports a raising rig.rb through notify' do
      write_rig(:project, 'raise "boom"')
      source.discover(autoload: false)

      assert_equal [[:error, "#{project_rig_path} failed to load: boom"]], @host.notifications
    end

    it "keeps the other file's extensions when one file raises" do
      write_rig(:home, recording('es_home'))
      write_rig(:project, 'raise "boom"')

      assert_equal %w[es_home], source.discover(autoload: false).map(&:name)
    end

    it 'skips the extensions a raising file recorded' do
      write_rig(:home, "#{recording('es_doomed')}raise 'boom'")

      assert_empty source.discover(autoload: false)
    end

    it 'tracks a raising file' do
      write_rig(:home, 'raise "boom"')
      discovered = source
      discovered.discover(autoload: false)

      assert_equal [home_rig_path], discovered.tracked_files
    end
  end

  describe '#rediscover' do
    def discovered
      built = source
      built.discover(autoload: false)
      built
    end

    it 'runs a tracked require_relative again' do
      write_local('counted', appending(marker))
      write_rig(:project, "require_relative 'counted'")
      discovered.rediscover

      assert_equal 'xx', File.read(marker)
    end

    it 'tracks the files of the rediscovery alone' do
      write_rig(:home, '')
      rediscovering = discovered
      FileUtils.rm(home_rig_path)
      rediscovering.rediscover

      assert_empty rediscovering.tracked_files
    end

    it 'reports a raising rig.rb as its message' do
      write_rig(:home, '')
      rediscovering = discovered
      write_rig(:home, 'raise "boom"')

      assert_equal "#{home_rig_path} failed to load: boom", rediscovering.rediscover
    end

    it 'leaves the notifying of a raising rig.rb to the caller' do
      write_rig(:home, '')
      rediscovering = discovered
      write_rig(:home, 'raise "boom"')
      rediscovering.rediscover

      assert_empty @host.notifications
    end

    it 'leaves the project file alone once the home file raised' do
      write_rig(:home, 'raise "boom"')
      write_rig(:project, appending(marker))
      source.rediscover

      refute_path_exists marker
    end

    it 'confirms a project rig.rb appearing after the discovery' do
      rediscovering = discovered
      write_rig(:project, '')
      rediscovering.rediscover

      assert_equal ["Trust #{project_rig_path}?"], @host.questions
    end

    it 'reports a raising project rig.rb as its message' do
      write_rig(:project, '')
      rediscovering = discovered
      write_rig(:project, 'raise "boom"')

      assert_equal "#{project_rig_path} failed to load: boom", rediscovering.rediscover
    end

    it 'returns the extensions a rewritten rig.rb records' do
      write_rig(:home, recording('es_home'))
      rediscovering = discovered
      write_rig(:home, recording('es_home_next'))

      assert_equal %w[es_home_next], rediscovering.rediscover.map(&:name)
    end

    it 'returns a re-recorded extension once, as the rewritten rig.rb records it' do
      write_rig(:home, recording('es_home'))
      rediscovering = discovered
      write_rig(:home, recording('es_home'))
      rediscovered = rediscovering.rediscover

      assert_equal [Riffer::Rig.extensions['es_home']], rediscovered
    end

    it 'drops the extensions of a deleted rig.rb' do
      write_rig(:home, recording('es_home'))
      rediscovering = discovered
      FileUtils.rm(home_rig_path)

      assert_empty rediscovering.rediscover
    end

    it 'keeps the gem extensions' do
      gem_file = write_gem_file(recording('es_gem'))
      rediscovering = source
      with_gem_files([gem_file]) { rediscovering.discover(autoload: true) }

      assert_equal %w[es_gem], rediscovering.rediscover.map(&:name)
    end

    it 'does not load the gem files again' do
      gem_file = write_gem_file(appending(marker))
      rediscovering = source
      with_gem_files([gem_file]) { rediscovering.discover(autoload: true) }
      with_gem_files([gem_file]) { rediscovering.rediscover }

      assert_equal 'x', File.read(marker)
    end
  end

  describe '#validated' do
    def failing
      Riffer::Rig::Extension.new('es_failing') { |_rig| raise 'boom' }
    end

    def passing
      Riffer::Rig::Extension.new('es_passing') { |_rig| nil }
    end

    it 'keeps an extension whose block runs' do
      extension = passing

      assert_equal [extension], source.validated([extension], {})
    end

    it 'drops an extension whose block raises' do
      extension = passing

      assert_equal [extension], source.validated([failing, extension], {})
    end

    it 'reports the dropped extension through notify' do
      source.validated([failing], {})

      assert_equal [[:error, 'Extension es_failing failed to load: boom']], @host.notifications
    end
  end

  describe '#file_state' do
    it 'stamps a missing rig.rb with nil' do
      assert_equal({ home_rig_path => nil, project_rig_path => nil }, source.file_state)
    end

    it 'stamps a rig.rb with its mtime' do
      write_rig(:home, '')

      assert_equal File.mtime(home_rig_path), source.file_state[home_rig_path]
    end

    it 'stamps the tracked files' do
      local = write_local('local', '')
      write_rig(:project, "require_relative 'local'")
      discovered = source
      discovered.discover(autoload: false)

      assert_equal [local, project_rig_path, home_rig_path], discovered.file_state.keys
    end
  end
end
