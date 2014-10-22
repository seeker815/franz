require 'thread'
require 'logger'

require 'eventmachine'

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

      @last_checkin = Time.new 0
      @checkin_interval = 60

      log.debug \
        event: 'tail started',
        watch_events: watch_events,
        tail_events: tail_events,
        block_size: block_size,
        opts: opts
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

    def checkin now=Time.now
      if @last_checkin < now - @checkin_interval
        log.warn event: 'checkin', cursors_size: @cursors.length
        @last_checkin = now
      end
    end

    def read path, size
      log.trace \
        event: 'read',
        path: path,
        size: size
      @cursors[path] ||= 0
      spread = size - @cursors[path]
      if spread > @read_limit
        log.warn event: 'large read', path: path, spread: spread
      end
      loop do
        break if @cursors[path] >= size

        begin
          data = IO::read path, @block_size, @cursors[path]
          if data.nil?
            log.fatal event: 'nil read', path: path
            next
          end
          size = data.bytesize
          buffer[path].extract(data).each do |line|
            tail_events.push path: path, line: line
          end
          @cursors[path] += size
        rescue RuntimeError
          log.fatal event: 'buffer full', path: path
        rescue EOFError, Errno::ENOENT
          # we're done here
        end
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
      checkin
      case event[:name]
      when :created
        # nop
      when :replaced
        log.warn event: 'replaced', raw: event
        close event[:path]
        read event[:path], event[:size]
      when :truncated
        log.warn event: 'truncated', raw: event
        close event[:path]
        read event[:path], event[:size]
      when :appended
        read event[:path], event[:size]
      when :deleted
        log.warn event: 'deleted', raw: event
        close event[:path]
      else
        log.warn event: 'invalid event', raw: event
        exit 2
      end
      return event[:path]
    end
  end
end