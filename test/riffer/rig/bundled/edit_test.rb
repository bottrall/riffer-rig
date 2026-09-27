# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Edit' do
  it 'is named edit' do
    assert_equal 'edit', Riffer::Rig::Bundled::Edit.name
  end

  it 'registers the edit tool' do
    registrar = Riffer::Rig::Registrar.new('edit')
    Riffer::Rig::Bundled::Edit.run(registrar)

    assert_equal({ 'edit' => Riffer::Rig::Tools::Edit }, registrar.tools)
  end
end
