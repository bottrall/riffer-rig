# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Read' do
  it 'is named read' do
    assert_equal 'read', Riffer::Rig::Bundled::Read.name
  end

  it 'registers the read tool' do
    registrar = Riffer::Rig::Registrar.new('read')
    Riffer::Rig::Bundled::Read.run(registrar)

    assert_equal({ 'read' => Riffer::Rig::Tools::Read }, registrar.tools)
  end
end
