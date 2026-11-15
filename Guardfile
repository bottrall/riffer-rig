# frozen_string_literal: true

# Run by bin/generate --watch.
guard :shell do
  watch(%r{^lib/.*\.rb$}) do
    system('bin/generate')
  end
end
