# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature 'sig/generated'
  signature 'sig/manual'
  signature 'sig/_private'

  check 'lib'

  collection_config 'rbs_collection.yaml'

  library 'date'
  library 'json'
  library 'open3'
  library 'io-console'

  configure_code_diagnostics(D::Ruby.all_error)
end
