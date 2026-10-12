# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Bundled do
  it 'keys each bundled extension by its name' do
    assert(Riffer::Rig::Bundled::BY_NAME.all? { |name, extension| extension.name == name.to_s })
  end
end
