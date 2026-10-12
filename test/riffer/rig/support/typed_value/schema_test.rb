# frozen_string_literal: true

require 'test_helper'

class SchemaDeclared
  extend Riffer::Rig::Support::TypedValue::Schema

  typed_value :declared, :row, :col
end

class SchemaStringTyped
  extend Riffer::Rig::Support::TypedValue::Schema

  typed_value 'label', :row, :col
end

describe Riffer::Rig::Support::TypedValue::Schema do
  it 'exposes the declared type' do
    assert_equal :declared, SchemaDeclared.type
  end

  it 'keeps a string type a string' do
    assert_equal 'label', SchemaStringTyped.type
  end

  it 'exposes the declared attributes in order' do
    assert_equal %i[row col], SchemaDeclared.attributes
  end

  it 'freezes the attribute list' do
    assert_predicate SchemaDeclared.attributes, :frozen?
  end
end
