# frozen_string_literal: true

# Isolate the suite from the developer's real home: anything under ~/.riffer
# or ~/.agents (settings, auth, AGENTS.md, skills directories) must not change
# what the tests assert. Created before riffer is required, so every Dir.home
# and ~ expansion in lib resolves here.
require 'fileutils'
require 'tmpdir'

TEST_HOME = Dir.mktmpdir('riffer-test-home') #: String
ENV['HOME'] = TEST_HOME
# The Anthropic SDK's credential chain reads these, so a developer's own would
# decide whether the suite is asked for an Anthropic key.
ENV.delete_if { |name, _value| name.start_with?('ANTHROPIC_') }
at_exit { FileUtils.remove_entry(TEST_HOME) }

require 'minitest/autorun'
require 'minitest/spec'
require 'riffer/rig'
