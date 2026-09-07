# frozen_string_literal: true

require 'io/console'

module Riffer::Rig::CLI
  extend self

  PROVIDER_URLS = {
    'anthropic' => 'https://console.anthropic.com/settings/keys',
    'openai' => 'https://platform.openai.com/api-keys',
    'gemini' => 'https://aistudio.google.com/app/apikey',
    'openrouter' => 'https://openrouter.ai/keys'
  }.freeze

  def start(output: $stdout, input: $stdin)
    theme = Riffer::Rig::UI::Theme.for(output)

    model    = Riffer::Rig::Settings.model
    provider = Riffer::Rig::Settings.provider_for(model)

    api_key = (provider && Riffer::Rig::Credentials.api_key_for(provider)) ||
              onboard(provider, theme, output:, input:)
    return 1 if api_key.nil?

    configure_provider(provider, api_key)

    agent    = Riffer::Rig::CodingAgent.new
    animator = Riffer::Rig::UI::Animator.new(io: output, theme:)

    reveal_banner(theme, animator, model)

    tally    = Riffer::Rig::TokenTally.new(pricing: Riffer::Rig::Settings.pricing_for(model))
    renderer = Riffer::Rig::UI::Renderer.new(io: output, theme:, tally:)
    Riffer::Rig::REPL.new(agent:, renderer:, animator:, theme:, input:, output:).run
    0
  end

  private

  def configure_provider(provider, api_key)
    case provider
    when 'anthropic'  then Riffer.configure { |c| c.anthropic.api_key  = api_key }
    when 'openai'     then Riffer.configure { |c| c.openai.api_key     = api_key }
    when 'gemini'     then Riffer.configure { |c| c.gemini.api_key     = api_key }
    when 'openrouter' then Riffer.configure { |c| c.openrouter.api_key = api_key }
    end
  end

  def onboard(provider, theme, output:, input:)
    url  = (provider && PROVIDER_URLS[provider]) || 'your provider'
    name = provider ? provider.capitalize : 'provider'

    output.puts(theme.cyan('♪ welcome to riffer-rig ♪'))
    output.puts(theme.grey("No #{name} API key found. Create one at #{url}"))
    output.print("#{theme.pink('›')} Paste your #{name} API key #{theme.grey('(hidden)')}: ")

    key = read_secret(input).to_s.strip
    output.puts

    if key.empty?
      output.puts(theme.grey("No key entered. Set #{env_var_for(provider)} or re-run riffer to try again."))
      return nil
    end

    Riffer::Rig::Credentials.save_api_key(provider, key) if provider
    output.puts(theme.grey("Saved to #{Riffer::Rig::Credentials::PATH} (permissions 600)."))
    key
  end

  def env_var_for(provider)
    (provider && Riffer::Rig::Credentials::PROVIDER_ENV_VARS[provider]) || 'the appropriate API key env var'
  end

  def read_secret(input)
    return input.noecho(&:gets) if input.respond_to?(:noecho) && input.tty?

    input.gets
  end

  def reveal_banner(theme, animator, model)
    loaded  = [Riffer::Rig::CodingAgent::GLOBAL_AGENTS_FILE, File.join(Dir.pwd, 'AGENTS.md')].select { |path| File.file?(path) }
    context = loaded.empty? ? 'none' : loaded.join(', ')

    glints = Riffer::Rig::UI::Riffy::GLINT_COLS + [nil]
    frames = glints.map do |glint_col|
      Riffer::Rig::UI::Banner.lines(theme, model: model, cwd: Dir.pwd, context: context, skills: count_skills, version: Riffer::Rig::VERSION, glint_col: glint_col)
    end
    animator.reveal(frames)
  end

  def count_skills
    dirs    = [Riffer::Rig::CodingAgent::GLOBAL_SKILLS_DIR, Riffer::Rig::CodingAgent::PROJECT_SKILLS_DIR.call]
    backend = Riffer::Skills::FilesystemBackend.new(*dirs)
    count   = backend.list_skills.length
    count.zero? ? 'none' : count.to_s
  rescue StandardError
    'none'
  end
end
