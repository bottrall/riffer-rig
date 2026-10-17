# frozen_string_literal: true

module StdinPipes
  def pipe
    IO.pipe.tap { |ends| pipe_ends.concat(ends) }
  end

  def piped(text)
    reader, writer = pipe
    writer.write(text)
    writer.close
    reader
  end

  def close_pipes
    pipe_ends.each(&:close)
  end

  private

  def pipe_ends
    @pipe_ends ||= []
  end
end
