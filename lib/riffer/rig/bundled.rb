# frozen_string_literal: true

module Riffer::Rig::Bundled
  BY_NAME = { read: Read, write: Write, edit: Edit, bash: Bash }.freeze #: Hash[Symbol, Riffer::Rig::Extension]
end
