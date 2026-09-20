# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'tmpdir'
require 'riffer/rig'

module Minitest::Assertions
  def assert_implements(base, subclass)
    inherited = base.public_instance_methods(false) - subclass.public_instance_methods(false)

    assert_empty inherited, "#{subclass} leaves #{inherited.join(', ')} to the abstract #{base}"
  end
end
