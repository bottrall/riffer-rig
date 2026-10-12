# frozen_string_literal: true

module RigFiles
  def write_rig(scope, body)
    root = scope == :home ? @home : @cwd
    FileUtils.mkdir_p(File.join(root, '.riffer'))
    File.write(File.join(root, '.riffer', 'rig.rb'), body)
  end

  def project_rig_path
    File.expand_path(File.join(@cwd, '.riffer', 'rig.rb'))
  end

  def with_gem_files(paths)
    original = Gem.method(:find_files)
    Gem.define_singleton_method(:find_files) { |_glob| paths }
    yield
  ensure
    Gem.define_singleton_method(:find_files, original)
  end
end
