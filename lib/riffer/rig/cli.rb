# frozen_string_literal: true

require 'io/console'

module Riffer::Rig::CLI
  extend self

  # @rbs output: IO
  # @rbs input: IO
  # @rbs model: String
  # @rbs return: Integer
  def start(output: $stdout, input: $stdin, model: Riffer::Rig::Settings.model)
    theme = Riffer::Rig::UI::Theme.for(output)

    provider = Riffer::Rig::Settings.provider_for(model)

    if provider
      values = credentials_for(provider, theme, output:, input:)
      return 1 if values.nil?

      Riffer::Rig::Credentials.apply(provider, values)
    end

    agent    = Riffer::Rig::CodingAgent.new
    animator = Riffer::Rig::UI::Animator.new(io: output, theme:)

    reveal_banner(theme, animator, model)

    tally    = Riffer::Rig::TokenTally.new(pricing: Riffer::Rig::Settings.pricing_for(model))
    smoother = Riffer::Rig::UI::Smoother.new(io: output, theme:)
    renderer = Riffer::Rig::UI::Renderer.new(io: output, theme:, tally:, smoother:)
    Riffer::Rig::REPL.new(agent:, renderer:, animator:, theme:, smoother:, input:, output:).run
    0
  end

  private

  # @rbs provider: String
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs output: IO
  # @rbs input: IO
  # @rbs return: Hash[Symbol, String]?
  def credentials_for(provider, theme, output:, input:)
    resolution = Riffer::Rig::Credentials.resolve(provider, host: Riffer::Rig::Hosts::Null.new)
    return resolution.values if resolution.missing.empty?

    onboard(provider, resolution, theme, output:, input:)
  end

  # @rbs provider: String
  # @rbs resolution: Riffer::Rig::Credentials::Resolution
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs output: IO
  # @rbs input: IO
  # @rbs return: Hash[Symbol, String]?
  def onboard(provider, resolution, theme, output:, input:)
    recipe = Riffer::Rig::Recipes.for(provider)
    missing = recipe[:fields].select { |field| resolution.missing.include?(field[:name]) }

    output.puts(theme.cyan('♪ welcome to riffer-rig ♪'))
    output.puts(theme.grey("No #{provider} credentials found. Create them at #{recipe[:url] || 'your provider'}"))

    answers = missing.to_h { |field| [field[:name], prompt(provider, field, theme, output:, input:)] }
    if answers.values.any?(&:empty?)
      env_vars = missing.flat_map { |field| field[:env] }.join(', ')
      output.puts(theme.grey("Nothing entered. Set #{env_vars} or re-run riffer to try again."))
      return nil
    end

    Riffer::Rig::Credentials.store(provider, answers)
    output.puts(theme.grey("Saved under #{File.dirname(Riffer::Rig::Credentials::PATH)} (auth.json permissions 600)."))
    resolution.values.merge(answers)
  end

  # @rbs provider: String
  # @rbs field: Riffer::Rig::Recipes::field
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs output: IO
  # @rbs input: IO
  # @rbs return: String
  def prompt(provider, field, theme, output:, input:)
    hint = field[:secret] ? " #{theme.grey('(hidden)')}" : ''
    output.print("#{theme.pink('›')} Paste your #{provider} #{field[:name]}#{hint}: ")

    answer = (field[:secret] ? read_secret(input) : input.gets).to_s.strip
    output.puts
    answer
  end

  # @rbs input: IO
  # @rbs return: String?
  def read_secret(input)
    return input.noecho(&:gets) if input.respond_to?(:noecho) && input.tty?

    input.gets
  end

  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs animator: Riffer::Rig::UI::Animator
  # @rbs model: String
  # @rbs return: void
  def reveal_banner(theme, animator, model)
    loaded  = [Riffer::Rig::CodingAgent::GLOBAL_AGENTS_FILE, File.join(Dir.pwd, 'AGENTS.md')].select { |path| File.file?(path) }
    context = loaded.empty? ? 'none' : loaded.join(', ')

    animator.reveal(
      [Riffer::Rig::UI::Banner.lines(
        theme,
        model: model,
        cwd: Dir.pwd,
        context: context,
        skills: count_skills,
        version: Riffer::Rig::VERSION
      )]
    )
  end

  # @rbs return: String
  def count_skills
    dirs    = [Riffer::Rig::CodingAgent::GLOBAL_SKILLS_DIR, Riffer::Rig::CodingAgent::PROJECT_SKILLS_DIR.call]
    backend = Riffer::Skills::FilesystemBackend.new(*dirs)
    count   = backend.list_skills.length
    count.zero? ? 'none' : count.to_s
  rescue StandardError
    'none'
  end
end
