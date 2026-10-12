# frozen_string_literal: true

require 'test_helper'
require_relative '../support/confirming_host'
require_relative '../support/rig_files'

describe 'automatic reload of a rig.rb the agent edits mid-turn' do
  include RigFiles

  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    write_rig(:project, editor_rig)
    @runtime = Riffer::Rig::Loader.runtime(
      cwd: @cwd,
      host: ConfirmingHost.new([true]),
      env: Riffer::Rig::Env.new({ 'MOCK_API_KEY' => 'mock-key' }),
      home: @home,
      riffer_config: Riffer::Config.new,
      store: nil,
      options: Riffer::Rig::Loader::Options.new(model: 'mock/test')
    )
    call_tool('editor')
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def editor_rig
    <<~RUBY
      class EditorTool < Riffer::Tool
        identifier 'editor'
        description 'edits the rig'
        def call(context:)
          File.write(#{project_rig_path.inspect}, <<~INNER)
            class ProbeNextTool < Riffer::Tool
              identifier 'probe_next'
              description 'probe'
              def call(context:) = text('probe')
            end
            Riffer::Rig.extension('probe') { |rig| rig.tool ProbeNextTool }
          INNER
          text('edited')
        end
      end
      Riffer::Rig.extension('probe') { |rig| rig.tool EditorTool }
    RUBY
  end

  def call_tool(name)
    @runtime.agent.provider.stub_response('', tool_calls: [{ name: name, arguments: '{}' }])
    @runtime.agent.provider.stub_response('done')
    @runtime.ask("use #{name}")
  end

  it 'registers the tool the edit added' do
    assert_includes @runtime.agent.tools.map(&:identifier), 'probe_next'
  end

  it 'serves the next request with the reloaded tools' do
    tool = call_tool('probe_next').messages.rfind { |message| message.is_a?(Riffer::Messages::Tool) }

    assert_equal 'probe', tool.content
  end
end
