# frozen_string_literal: true

require_relative 'lib/riffer/rig/version'

Gem::Specification.new do |spec|
  spec.name = 'riffer-rig'
  spec.version = Riffer::Rig::VERSION
  spec.authors = ['Jake Bottrall']
  spec.email = ['jakebottrall@gmail.com']

  spec.summary = 'A dead-simple terminal coding agent built on riffer.'
  spec.description = 'An interactive terminal coding agent (read/write/edit/bash) built on the riffer agentic framework.'
  spec.homepage = 'https://github.com/bottrall/riffer-rig'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['changelog_uri'] = 'https://github.com/bottrall/riffer-rig/blob/main/CHANGELOG.md'
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files = Dir['lib/**/*.rb', 'exe/*', 'sig/generated/**/*', 'sig/manual/**/*', 'README.md', 'CHANGELOG.md']
  spec.bindir = 'exe'
  spec.executables = ['riffer']
  spec.require_paths = ['lib']

  spec.add_dependency 'anthropic', '~> 1.69'
  spec.add_dependency 'base64', '~> 0.2'
  spec.add_dependency 'openai', '~> 0.80'
  spec.add_dependency 'riffer', '~> 0.45.0'
  spec.add_dependency 'zeitwerk', '~> 2.8'
end
