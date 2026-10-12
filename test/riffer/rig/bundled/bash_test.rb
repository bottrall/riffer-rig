# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Bash' do
  it 'registers the bash tool' do
    registrar = Riffer::Rig::Registrar.new('bash')
    Riffer::Rig::Bundled::Bash.run(registrar)

    assert_equal({ 'bash' => Riffer::Rig::Tools::Bash }, registrar.tools)
  end
end
