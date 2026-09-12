# frozen_string_literal: true

require 'date'

class Riffer::Rig::CodingAgent < Riffer::Agent
  GLOBAL_AGENTS_FILE = File.expand_path('~/.riffer/AGENTS.md') #: String

  GLOBAL_SKILLS_DIR  = File.expand_path('~/.riffer/skills') #: String

  PROJECT_SKILLS_DIR = -> { File.join(Dir.pwd, '.skills') } #: ^() -> String

  model Riffer::Rig::Settings.model
  model_options Riffer::Rig::Settings.model_options

  uses_tools [
    Riffer::Rig::Tools::Read,
    Riffer::Rig::Tools::Write,
    Riffer::Rig::Tools::Edit,
    Riffer::Rig::Tools::Bash
  ]

  skills do
    backend(->(_ctx) { Riffer::Skills::FilesystemBackend.new(GLOBAL_SKILLS_DIR, PROJECT_SKILLS_DIR.call) })
  end

  max_steps nil

  instructions(
    lambda do
      context_files = [GLOBAL_AGENTS_FILE, File.join(Dir.pwd, 'AGENTS.md')]
        .select { |path| File.file?(path) }
        .map { |path| "<project_instructions path=\"#{path}\">\n#{File.read(path)}\n</project_instructions>" }

      project_context =
        if context_files.empty?
          ''
        else
          "\n\n<project_context>\n#{context_files.join("\n\n")}\n</project_context>"
        end

      <<~PROMPT.chomp + project_context + "\n\nCurrent date: #{Date.today}\nCurrent working directory: #{Dir.pwd}"
        You are an expert coding assistant running inside riffer-rig, a terminal coding agent. You help the user by reading files, running shell commands, editing code, and writing new files.

        Available tools:
        - read: read a file's contents
        - write: write content to a file
        - edit: replace an exact string in a file
        - bash: run a shell command in the working directory

        Guidelines:
        - Be concise and direct in your responses.
        - Show file paths clearly when working with files.
        - Use bash for file exploration (ls, rg, find) rather than guessing.
        - Prefer editing existing files over creating new ones.
      PROMPT
    end
  )
end
