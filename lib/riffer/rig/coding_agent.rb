# frozen_string_literal: true

require 'date'

class Riffer::Rig::CodingAgent < Riffer::Agent
  model Riffer::Rig::Settings.model
  model_options Riffer::Rig::Settings.model_options

  uses_tools [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Write, Riffer::Rig::Tools::Edit, Riffer::Rig::Tools::Bash]

  skills do
    backend(->(_ctx) { Riffer::Skills::FilesystemBackend.new(*Riffer::Rig::SkillDirectories.for(Dir.pwd)) })
  end

  max_steps nil

  instructions(
    lambda do
      base = <<~PROMPT.chomp
        You are an expert coding assistant running inside riffer-rig, a terminal coding agent. You help the user by reading files, running shell commands, editing code, and writing new files.

        Available tools:
        - read: read a file's contents
        - write: write content to a file
        - edit: replace an exact string in a file
        - bash: run a shell command in the working directory

        Guidelines:
        - Be concise and direct in your responses.
        - Show file paths clearly when working with files.
      PROMPT

      environment = "Current date: #{Date.today}\nCurrent working directory: #{Dir.pwd}"

      [base, Riffer::Rig::Prompts::AgentsMd.section(Dir.pwd), environment].compact.join("\n\n")
    end
  )
end
