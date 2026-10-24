# frozen_string_literal: true

module HostNamespace
  RIG_CONSTANT = /Riffer::Rig::([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)/

  def rig_constants_outside(namespace)
    lib = File.expand_path('../../lib/riffer/rig', __dir__)
    stem = namespace.downcase
    sources = [File.join(lib, "#{stem}.rb"), *Dir[File.join(lib, stem, '**', '*.rb')]]
    sources.flat_map { |path| File.read(path).scan(RIG_CONSTANT).flatten }
           .reject { |path| path == namespace || path.start_with?("#{namespace}::") }
           .uniq
  end
end
