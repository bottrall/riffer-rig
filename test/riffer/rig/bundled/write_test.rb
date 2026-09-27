# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Write' do
  it 'is named write' do
    assert_equal 'write', Riffer::Rig::Bundled::Write.name
  end

  it 'registers the write tool' do
    registrar = Riffer::Rig::Registrar.new('write')
    Riffer::Rig::Bundled::Write.run(registrar)

    assert_equal({ 'write' => Riffer::Rig::Tools::Write }, registrar.tools)
  end
end
