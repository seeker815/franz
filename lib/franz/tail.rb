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
      @spread_size = opts[:spread_size] || (2*@block_size)
      @cursors     = opts[:cursors]     || Hash.new { |h,k| h[k] = 0 }
      @logger      = opts[:logger]      || Logger.new(STDOUT)

      log.debug 'tail: watch_events=%s tail_events=%s' % [
        @watch_events, @tail_events
      ]

      @buffer = Hash.new { |h, k| h[k] = BufferedTokenizer.new }
      @stop   = false

      @tail_thread = Thread.new do
        until @stop
          started = Time.now
          handle(watch_events.shift)
          elapsed = Time.now - started
          log.fatal 'tail ended: elapsed=%fs (watch_events.size=%d tail_events.size=%d)' % [
            elapsed, watch_events.size, tail_events.size
          ]
        end
      end

      log.debug 'started tail'
    end

    # Stop the Tail thread. Effectively only once.
    #
    # @return [Hash] internal "cursors" state
    def stop
      return state if @stop
      @stop = true
      @watch_thread.kill rescue nil
      @tail_thread.kill  rescue nil
      log.debug 'stopped tail'
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
      started = Time.now
      pos = @cursors[path]

      raise if size.nil?
      loop do
        break if @cursors[path] >= size

        begin
          data = IO::read path, @block_size, @cursors[path]
          @cursors[path] += data.bytesize
          buffer[path].extract(data).each do |line|
            log.trace 'captured: path=%s line=%s' % [ path, line ]
            tail_events.push path: path, line: line
          end
        rescue EOFError, Errno::ENOENT
          # we're done here
        end
      end

      diff = @cursors[path] - pos
      elapsed = Time.now - started
      log.trace 'read: path=%s size=%s cursor=%s (diff=%d) [elapsed=%0.2fs]' % [
        path.inspect, size.inspect, @cursors[path].inspect, diff, elapsed
      ]
    end

    def close path
      @cursors.delete(path)
      log.debug 'closed: path=%s' % path.inspect
    end

    def handle event
      log.trace 'handle: event=%s' % event.inspect
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