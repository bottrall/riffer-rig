# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Bundled do
  it 'lists the bundled extensions by name in load order' do
    assert_equal %i[read write edit bash agents_md], Riffer::Rig::Bundled::BY_NAME.keys
  end

  it 'keys each bundled extension by its name' do
    assert(Riffer::Rig::Bundled::BY_NAME.all? { |name, extension| extension.name == name.to_s })
  end

  it 'keeps the bundled extensions out of the process registry' do
    assert_empty Riffer::Rig.extensions.keys & %w[read write edit bash agents_md]
  end
end
