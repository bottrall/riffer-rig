# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature 'sig/generated'
  signature 'sig/manual'
  signature 'sig/_private'

  check 'lib'

  library 'date'
  library 'fileutils'
  library 'io-console'
  library 'json'
  library 'open3'
  library 'riffer'

  configure_code_diagnostics(D::Ruby.all_error)
end
