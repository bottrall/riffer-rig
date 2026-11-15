# frozen_string_literal: true

require_relative 'lib/riffer/rig/version'

Gem::Specification.new do |spec|
  spec.name = 'riffer-rig'
  spec.version = Riffer::Rig::VERSION
  spec.authors = ['Jake Bottrall']
  spec.email = ['jakebottrall@gmail.com']

  spec.summary = 'A dead-simple terminal coding agent built on riffer.'
  spec.description = 'An interactive terminal agent (read/write/edit/bash) built on the riffer agentic framework.'
  spec.homepage = 'https://github.com/bottrall/riffer-rig'
  spec.license = 'MIT'
  # Every Ruby that isn't end-of-life.
  spec.required_ruby_version = '>= 3.3'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['changelog_uri'] = 'https://github.com/bottrall/riffer-rig/blob/main/CHANGELOG.md'
  spec.metadata['source_code_uri'] = spec.homepage

  # sig/_private ships too: RBS skips `_`-prefixed directories when the gem's
  # signatures are loaded as a library, so its stubs stay private.
  spec.files = Dir['lib/**/*.rb', 'exe/*', 'sig/**/*.rbs', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = ['riffer']
  spec.require_paths = ['lib']

  spec.add_dependency 'acp-sdk', '~> 0.14.0'
  spec.add_dependency 'base64', '~> 0.3'
  spec.add_dependency 'event_stream_parser', '~> 1.0'
  spec.add_dependency 'faraday', '~> 2.14'
  spec.add_dependency 'mcp', '~> 1.6'
  spec.add_dependency 'riffer', '~> 0.55.0'
  spec.add_dependency 'zeitwerk', '~> 2.8'
end
