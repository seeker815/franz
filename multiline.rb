require_relative './object_builder'
require_relative './sash'

Thread.abort_on_exception = true

Multiline = Object.new

Object(Multiline) { |o|

  o.new = ->(opts) {
    @configs          = opts[:configs]          || []
    @tail_events      = opts[:tail_events]      || []
    @multiline_events = opts[:multiline_events] || []
    @flush_interval   = opts[:flush_interval]   || 5
    @lock             = Mutex.new
    @buffer           = Sash.new
    @seq              = Hash.new { |h, k| h[k] = 0 }

    Thread.new do
      loop do
        flush
        sleep flush_interval
      end
    end

    Thread.new do
      loop do
        capture
      end
    end
  }

private
  attr_reader :configs, :tail_events, :multiline_events, :flush_interval

  attr_reader :lock, :buffer, :seq

  o.config_with_type = ->(type) {
    configs.select { |c| c[:type] == type }.shift
  }

  o.enqueue = ->(type, path, message) {
    multiline_events.push type: type, path: path, message: message, seq: seq[path] += 1
  }

  o.capture = -> {
    event     = tail_events.shift
    config    = config_with_type event[:type]
    multiline = config[:multiline]

    if multiline.nil?
      enqueue event[:type], event[:path], event[:line]
    else
      lock.synchronize do
        if event[:line] =~ multiline
          buffered = buffer.flush(event[:path])
          lines = buffered.map { |e| e[:line] }
          unless lines.empty?
            enqueue event[:type], event[:path], lines.join("\n")
          end
        end
        buffer.insert event[:path], event
      end
    end
  }

  o.flush = -> {
    lock.synchronize do
      started = Time.now
      buffer.keys.each do |path|
        if started - buffer.mtime(path) >= flush_interval
          buffered = buffer.remove(path)
          lines = buffered.map { |e| e[:line] }
          unless lines.empty?
            enqueue buffered[0][:type], path, lines.join("\n")
          end
        end
      end
    end
  }
}