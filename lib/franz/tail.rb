require 'thread'
require 'logger'

require 'eventmachine'

require_relative 'stats'


module Franz

  # Tail receives low-level file events from a Watch and handles the actual
  # reading of files, providing a stream of lines.
  class Tail
    ERR_BUFFER_FULL = 1
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

      @read_limit = opts[:read_limit] || 16_384 # 16 KiB
      @line_limit = opts[:line_limit] || nil    # no limit [KiB]
      @block_size = opts[:block_size] || 32_768 # 32 KiB
      @cursors    = opts[:cursors]    || Hash.new
      @logger     = opts[:logger]     || Logger.new(STDOUT)

      @nil_read = Hash.new { |h,k| h[k] = false }
      @buffer = Hash.new { |h, k| h[k] = BufferedTokenizer.new("\n", @line_limit) }
      @stop = false

      @statz = opts[:statz] || Franz::Stats.new
      @statz.create :num_reads, 0
      @statz.create :num_rotates, 0
      @statz.create :num_deletes, 0

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
      log.debug \
        event: 'read',
        file: path,
        size: size
      @cursors[path] ||= 0
      spread = size - @cursors[path]

      # A negative spread size means we've probably worked ahead of ourselves.
      # In such a case, we'll ignore the request, as it's likely been fulfilled.
      # We only need to worry if the spread size grows larger than the block
      # size--that means something other than us reading threw Franz off...
      if spread < 0
        if spread.abs > @block_size
          log.warn \
            event: 'large spread',
            file: path,
            size: size,
            cursor: @cursors[path],
            spread: spread
        end
        return
      end

      if spread > @read_limit
        log.warn \
          event: 'large read',
          file: path,
          size: size,
          cursor: @cursors[path],
          spread: spread
      end

      loop do
        break if @cursors[path] >= size

        begin
          data = IO::read path, @block_size, @cursors[path]
          reason_for_nil_data = 'unknown'
        rescue EOFError
          data = nil
          reason_for_nil_data = 'eof'
        rescue Errno::ENOENT
          data = nil
          reason_for_nil_data = 'noent'
        rescue Errno::EACCES
          data = nil
          reason_for_nil_data = 'access'
        end

        if data.nil?
          # Not so sure of myself here: It's been truncated, it's been rotated,
          # or else it no longer exists. We "return" in hopes that a :truncated,
          # :rotated, :deleted event comes along soon after. If it doesn't...
          log.error \
            event: 'nil read',
            file: path,
            size: size,
            cursor: @cursors[path],
            spread: (size - @cursors[path]),
            reason: reason_for_nil_data
          @nil_read[path] = true
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
            file: path,
            size: size,
            cursor: @cursors[path],
            spread: (size - @cursors[path])
          exit ERR_BUFFER_FULL
        end

        @cursors[path] += data_size
      end

      if @cursors[path] < size
        log.fatal \
          event: 'incomplete read',
          file: path,
          size: size,
          cursor: @cursors[path],
          spread: (size - @cursors[path])
        exit ERR_INCOMPLETE_READ
      end
    end


    def close path
      log.debug event: 'close', file: path
      tail_events.push path: path, line: buffer[path].flush
      @nil_read.delete path
      @cursors[path] = 0
    end


    def handle event
      path, size = event[:path], event[:size]
      log.debug \
        event: 'handle',
        raw: event
      case event[:name]

      when :deleted
        @statz.inc :num_deletes
        close path

      when :replaced, :truncated
        @statz.inc :num_rotates
        close path
        read path, size

      when :appended
        # Ignore read requests after a nil read. We'll wait for the next
        # event that tells us to close the file. Fingers crossed...
        unless @nil_read[path]
          @statz.inc :num_reads
          read path, size

        else # following a nil read
          log.debug \
            event: 'skipping read',
            raw: event
        end

      else
        log.fatal event: 'invalid event', raw: event
        exit ERR_INVALID_EVENT
      end

      return path
    end
  end
end