# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Bash' do
  it 'is named bash' do
    assert_equal 'bash', Riffer::Rig::Bundled::Bash.name
  end

  it 'registers the bash tool and its job companions' do
    registrar = Riffer::Rig::Registrar.new('bash')
    Riffer::Rig::Bundled::Bash.run(registrar)

    assert_equal(
      {
        'bash' => Riffer::Rig::Tools::Bash,
        'bash_poll' => Riffer::Rig::Tools::Bash::Poll,
        'bash_kill' => Riffer::Rig::Tools::Bash::Kill
      },
      registrar.tools
    )
  end
end
