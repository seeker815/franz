require 'buftok'

require_relative './object_builder'

Thread.abort_on_exception = true

Tail = Object.new

Object(Tail) { |o|

  o.new = ->(opts) {
    watch_events = opts[:watch_events] || []
    tail_events  = opts[:tail_events]  || []

    Thread.new do
      file, buffer = {}, Hash.new { |h, k| h[k] = BufferedTokenizer.new }
      loop do
        watch_event = watch_events.shift
        case watch_event[:name]
        when :created
          file = open file, watch_event
        when :replaced
          file = close file, watch_event
          file = open file, watch_event
          file, buffer = read file, buffer, watch_event, tail_events
        when :truncated
          file = close file, watch_event
          file = open file, watch_event
          file, buffer = read file, buffer, watch_event, tail_events
        when :appended
          file, buffer = read file, buffer, watch_event, tail_events
        when :deleted
          file = close file, watch_event
        else
          raise 'Invalid watch event'
        end
      end
    end

    return self
  }

private
  o.open = ->(file, event) {
    file[event[:path]] = File.open(event[:path])
    file[event[:path]].sysseek 0, IO::SEEK_SET
    return file
  }

  o.read = ->(file, buffer, event, q) {
    until file[event[:path]].pos >= event[:new_stat][:size]
      begin
        data = file[event[:path]].sysread(1048576) # 1 MiB
        buffer[event[:path]].extract(data).each do |line|
          q.push type: event[:type], path: event[:path], line: line
        end
      rescue EOFError
        # we're done here
      end
    end
    return file, buffer
  }

  o.close = ->(file, event) {
    file.delete(event[:path]).close
    return file
  }
}