require 'thread'
require 'logger'

require 'eventmachine'

module Franz

  # Tail receives low-level file events from a Watch and handles the actual
  # reading of files, providing a stream of lines.
  class Tail
    ERR_NIL_READ = 1
    ERR_INVALID_EVENT = 2
    ERR_INCOMPLETE_READ = 3

    attr_reader :cursors

    # Start a new Tail thread in the background.
    #
    # @param opts [Hash] a complex Hash for tail configuration
    # @option opts [InputConfig] :input_config shared Franz configuration
    def initialize opts={}
      @ic = opts[:input_config] || raise('No input_config specified')

      @watch_events = opts[:watch_events] || []
      @tail_events  = opts[:tail_events]  || []

      @read_limit = opts[:read_limit] || 10_240 # 100 KiB
      @line_limit = opts[:line_limit] || 10_240 # 10 KiB
      @block_size = opts[:block_size] || 32_768 # 32 KiB
      @cursors    = opts[:cursors]    || Hash.new
      @logger     = opts[:logger]     || Logger.new(STDOUT)

      @buffer = Hash.new { |h, k| h[k] = BufferedTokenizer.new("\n", @line_limit) }
      @stop   = false

      @tail_thread = Thread.new do
        handle(watch_events.shift) until @stop
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
      log.trace \
        event: 'read',
        path: path,
        size: size
      @cursors[path] ||= 0
      spread = size - @cursors[path]

      if spread <= 0
        log.trace \
          event: 'ignoring read',
          path: path,
          size: size,
          cursor: @cursors[path],
          spread: spread
        return
      end

      if spread > @read_limit
        log.trace \
          event: 'large read',
          path: path,
          size: size,
          cursor: @cursors[path],
          spread: spread
      end

      loop do
        break if @cursors[path] >= size

        begin
          data = IO::read path, @block_size, @cursors[path]
        rescue EOFError, Errno::ENOENT
          next
        end

        # Handle issue with IO::read, which seems to return nil when
        # the file in question has been rotated. In such a case, we'll
        # just reset the cursor and bail; hopefully we'll get a
        # "rotated" event from Watch in the near future.
        if data.nil?
          log.warn \
            event: 'nil read',
            path: path,
            size: size,
            cursor: @cursors[path],
            spread: (size - @cursors[path])
          @cursors[path] = 0
          return
        end
        data_size = data.bytesize

        begin
          buffer[path].extract(data).each do |line|
            tail_events.push path: path, line: line
          end
        rescue RuntimeError
          log.fatal \
            event: 'buffer full',
            path: path,
            size: size,
            cursor: @cursors[path],
            spread: (size - @cursors[path])
          exit ERR_NIL_READ
        end

        @cursors[path] += data_size
      end

      if @cursors[path] < size
        log.fatal \
          event: 'incomplete read',
          path: path,
          size: size,
          cursor: @cursors[path],
          spread: (size - @cursors[path])
        exit ERR_INCOMPLETE_READ
      end
    end

    def close path
      log.trace event: 'close', path: path
      tail_events.push path: path, line: buffer[path].flush
      @cursors[path] = 0
    end

    def handle event
      log.trace \
        event: 'handle',
        raw: event
      case event[:name]
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
        log.fatal event: 'invalid event', raw: event
        exit ERR_INVALID_EVENT
      end
      return event[:path]
    end
  end
end