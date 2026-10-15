# frozen_string_literal: true

class Riffer::Rig::Headless
  USAGE_ERROR = 2 #: Integer

  JOB_IDLE_TIMEOUT = 600 #: Integer

  # @rbs @input: IO
  # @rbs @output: IO
  # @rbs @error: IO
  # @rbs @host: Riffer::Rig::Headless::Host
  # @rbs @verbose: bool
  # @rbs @json: bool
  # @rbs @job_idle_timeout: Integer
  # @rbs @streamed_text: bool

  # @rbs input: IO
  # @rbs output: IO
  # @rbs error: IO
  # @rbs verbose: bool
  # @rbs json: bool
  # @rbs job_idle_timeout: Integer
  # @rbs return: Riffer::Rig::Headless
  def self.for(input:, output:, error:, verbose: false, json: false, job_idle_timeout: JOB_IDLE_TIMEOUT)
    host = Riffer::Rig::Headless::Host.new(error: error, json: json)
    new(
      input: input,
      output: output,
      error: error,
      host: host,
      verbose: verbose,
      json: json,
      job_idle_timeout: job_idle_timeout
    )
  end

  # @rbs input: IO
  # @rbs output: IO
  # @rbs error: IO
  # @rbs host: Riffer::Rig::Headless::Host
  # @rbs verbose: bool
  # @rbs json: bool
  # @rbs job_idle_timeout: Integer
  # @rbs return: void
  def initialize(input:, output:, error:, host:, verbose: false, json: false, job_idle_timeout: JOB_IDLE_TIMEOUT)
    @input = input
    @output = output
    @error = error
    @host = host
    @verbose = verbose
    @json = json
    @job_idle_timeout = job_idle_timeout
  end

  # @rbs prompt: String?
  # @rbs &build: (Riffer::Rig::Hosts::_Host) -> Riffer::Rig::Runtime
  # @rbs return: Integer
  def run(prompt:, &build)
    text = prompt_text(prompt)
    return usage_error if text.empty?

    drive(yield(@host), text)
  rescue Riffer::Rig::Loader::ConfigurationError => e
    fatal(e.message, USAGE_ERROR)
  rescue Interrupt
    130
  rescue StandardError => e
    fatal(e.message, 1)
  end

  private

  # @rbs prompt: String?
  # @rbs return: String
  def prompt_text(prompt)
    piped = @input.tty? ? '' : @input.read.to_s.strip
    [prompt, piped].compact.reject(&:empty?).join("\n\n")
  end

  # @rbs return: Integer
  def usage_error
    fatal('no prompt: pass one as an argument, or pipe it to stdin', USAGE_ERROR)
  end

  # @rbs message: String
  # @rbs code: Integer
  # @rbs return: Integer
  def fatal(message, code)
    if @json
      @output.write(Ndjson.error(message))
    else
      @error.puts("riffer: #{message}")
    end
    code
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs text: String
  # @rbs return: Integer
  def drive(runtime, text)
    code = turn(runtime) { |handler| runtime.prompt(text, &handler) }
    code = follow_up(runtime) while code.zero? && runtime.pending_jobs?
    code
  ensure
    runtime.close
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: Integer
  def follow_up(runtime)
    @error.puts('waiting for background jobs')
    cap = @job_idle_timeout unless @job_idle_timeout.zero?
    return abandon_jobs unless runtime.await_job_exit(timeout: cap)

    turn(runtime) { |handler| runtime.follow_up(&handler) }
  end

  # @rbs return: Integer
  def abandon_jobs
    message = "no background job exited in #{@job_idle_timeout}s; killing the jobs still running"
    if @json
      @output.write(Ndjson.line(Riffer::Rig::Events::Notify.new(message, :warning)))
    else
      @error.puts(message)
    end
    3
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs &: (^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void) -> void
  # @rbs return: Integer
  def turn(runtime)
    # @type var stop_reason: Symbol?
    stop_reason = nil
    # Runtime#cancel takes a Mutex, which Ruby refuses inside a trap handler,
    # so the handler hands the cancel to a thread.
    previous = Signal.trap('INT') { Thread.new { runtime.cancel } }
    begin
      yield(lambda do |event|
        case event
        when Riffer::Rig::Events::TurnEnd
          stop_reason = event.stop_reason
          @output.write(Ndjson.line(event)) if @json
        else
          handle(event)
        end
      end)
    rescue StandardError => e
      return fatal(e.message, 1)
    ensure
      Signal.trap('INT', previous)
    end
    finish(stop_reason)
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def handle(event)
    trace(event)
    return @output.write(Ndjson.line(event)) if @json

    case event
    when Riffer::StreamEvents::TextDelta
      @output.write(event.content)
      @streamed_text = true
    when Riffer::StreamEvents::TextDone
      # A provider that streams nothing hands over the whole text here; one
      # that streamed deltas has already written it.
      @output.write(event.content) if !@streamed_text && !event.content.empty?
      @output.puts if @streamed_text || !event.content.empty?
      @streamed_text = false
    end
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def trace(event)
    return unless @verbose

    case event
    when Riffer::StreamEvents::ToolCallDone
      @error.puts("tool_call #{event.name} #{event.arguments}")
    end
  end

  # @rbs stop_reason: Symbol?
  # @rbs return: Integer
  def finish(stop_reason)
    return 0 if stop_reason == :completed

    @error.puts("turn ended: #{stop_reason}") if stop_reason
    return 130 if stop_reason == Riffer::Rig::Runtime::INTERRUPT_CANCELLED
    return 3 if stop_reason && Riffer::Rig::Runtime::STOPPED_WITHOUT_COMPLETING.include?(stop_reason)

    1
  end
end
