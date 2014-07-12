require 'buftok'

require_relative './object_builder'

Thread.abort_on_exception = true

Tail = Object.new

Object(Tail) { |o|

  o.new = ->(opts) {
    @watch_events = opts[:watch_events] || []
    @tail_events  = opts[:tail_events]  || []

    @file   = Hash.new
    @buffer = Hash.new { |h, k| h[k] = BufferedTokenizer.new }

    Thread.new do
      loop do
        watch_event = watch_events.shift
        case watch_event[:name]
        when :created
          open watch_event
        when :replaced
          close watch_event
          open watch_event
          read watch_event
        when :truncated
          close file, watch_event
          open file, watch_event
          read watch_event
        when :appended
          read watch_event
        when :deleted
          close watch_event
        else
          raise 'Invalid watch event'
        end
      end
    end

    return self
  }

private
  attr_reader :watch_events, :tail_events, :file, :buffer

  o.open = ->(event) {
    file[event[:path]] = File.open(event[:path])
    file[event[:path]].sysseek 0, IO::SEEK_SET
  }

  o.read = ->(event) {
    until file[event[:path]].pos >= event[:new_stat][:size]
      begin
        data = file[event[:path]].sysread(1048576) # 1 MiB
        buffer[event[:path]].extract(data).each do |line|
          tail_events.push type: event[:type], path: event[:path], line: line
        end
      rescue EOFError
        # we're done here
      end
    end
  }

  o.close = ->(event) {
    file.delete(event[:path]).close
  }
}