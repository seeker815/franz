require 'thread'
require 'logger'

require 'buftok'

module Franz

  # Tail receives low-level file events from a Watch and handles the actual
  # reading of files, providing a stream of lines.
  class Tail
    attr_reader :cursors

    # Start a new Tail thread in the background.
    #
    # @param opts [Hash] a complex Hash for tail configuration
    def initialize opts={}
      @watch_events = opts[:watch_events] || []
      @tail_events  = opts[:tail_events]  || []

      @block_size  = opts[:block_size]  || 32_768 # 32 KiB
      @cursors     = opts[:cursors]     || Hash.new
      @logger      = opts[:logger]      || Logger.new(STDOUT)

      @buffer = Hash.new { |h, k| h[k] = BufferedTokenizer.new }
      @stop   = false

      @tail_thread = Thread.new do
        until @stop
          started = Time.now
          n = watch_events.size
          m = tail_events.size
          e = watch_events.shift
          elapsed2 = Time.now - started

          handle(e)
          elapsed1 = Time.now - started

          log.trace \
            event: 'tail finished',
            elapsed: elapsed1,
            elapsed_waiting_on_watch: elapsed2,
            elapsed_handling_event: (elapsed1 - elapsed2),
            watch_events_size_before: n,
            watch_events_size_after: watch_events.size,
            tail_events_size_before: m,
            tail_events_size_after: tail_events.size
        end
      end

      log.info \
        event: 'tail started',
        watch_events: watch_events,
        tail_events: tail_events,
        block_size: block_size
    end

    # Stop the Tail thread. Effectively only once.
    #
    # @return [Hash] internal "cursors" state
    def stop
      return state if @stop
      @stop = true
      @watch_thread.kill rescue nil
      @tail_thread.kill  rescue nil
      log.info event: 'tail stopped'
      return state
    end

    # Return the internal "cursors" state
    def state
      return @cursors.dup
    end

  private
    attr_reader :watch_events, :tail_events, :block_size, :cursors, :buffer, :reading

    def log ; @logger end

    def read path, size
      @cursors[path] ||= 0
      watch_events_size = watch_events.size
      tail_events_size = tail_events.size
      started = Time.now
      start_pos = @cursors[path]

      raise if size.nil?
      loop do
        break if @cursors[path] >= size

        begin
          pos = @cursors[path]
          data = IO::read path, @block_size, @cursors[path]
          @cursors[path] += data.bytesize
          num_lines = 0
          buffer[path].extract(data).each do |line|
            tail_events.push path: path, line: line
            num_lines += 1
          end
          diff = @cursors[path] - pos
          diff_start = @cursors[path] - start_pos
          elapsed = Time.now - started
          log.trace \
            event: 'tail capture finished',
            path: path,
            size: size,
            cursor: @cursors[path],
            diff: diff,
            diff_start: diff_start,
            elapsed: elapsed,
            watch_size: watch_events.size,
            tail_size: tail_events.size
        rescue EOFError, Errno::ENOENT, NoMethodError
          # we're done here
        end
      end

      diff = @cursors[path] - start_pos
      elapsed = Time.now - started
      log.trace \
        event: 'tail read finished',
        path: path,
        size: size,
        cursor: @cursors[path],
        diff: diff,
        elapsed: elapsed,
        watch_events_size_before: watch_events_size,
        watch_events_size_after: watch_events.size,
        tail_events_size_before: tail_events_size,
        tail_events_size_after: tail_events.size
    end

    def close path
      @cursors.delete(path)
      log.trace \
        event: 'tail closed',
        path: path
    end

    def handle event
      case event[:name]
      when :created
      when :replaced
        close event[:path]
        read event[:path], event[:size]
      when :truncated
        close event[:path]
        read event[:path], event[:size]
      when :appended
        read event[:path], event[:size]
      when :deleted
        close event[:path]
      else
        raise 'invalid event'
      end
    end
  end
end