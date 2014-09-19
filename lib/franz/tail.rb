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
          n = watch_events.size
          m = tail_events.size
          cp_started = Time.now

          e = watch_events.shift
          cp_deqeueued = Time.now

          path = handle(e)
          cp_handled = Time.now

          elapsed_total = cp_handled - cp_started
          elapsed_in_handle = cp_handled - cp_deqeueued
          elapsed_in_dequeue = cp_deqeueued - cp_started

          log.trace \
            event: 'tail finished',
            path: path,
            elapsed_total: elapsed_total,
            elapsed_in_dequeue: elapsed_in_dequeue,
            elapsed_in_handle: elapsed_in_handle,
            watch_events_size_before: n,
            watch_events_size_after: watch_events.size,
            tail_events_size_before: m,
            tail_events_size_after: tail_events.size
        end
      end

      log.debug \
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
      log.debug event: 'tail stopped'
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
      loop do
        break if @cursors[path] >= size

        begin
          data = IO::read path, @block_size, @cursors[path]
          buffer[path].extract(data).each do |line|
            tail_events.push path: path, line: line
          end
          @cursors[path] += data.bytesize
        rescue EOFError, Errno::ENOENT, NoMethodError
          # we're done here
        end
      end
    end

    def close path
      @cursors.delete(path)
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
      return event[:path]
    end
  end
end