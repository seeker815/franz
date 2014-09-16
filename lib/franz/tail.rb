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

      @eviction_interval = opts[:eviction_interval] || 60
      @block_size        = opts[:block_size]        || 32_768 # 32 KiB
      @spread_size       = opts[:spread_size]       || 98_304 # 96 KiB
      @cursors           = opts[:cursors]           || Hash.new
      @logger            = opts[:logger]            || Logger.new(STDOUT)

      log.debug 'tail: watch_events=%s tail_events=%s' % [
        @watch_events, @tail_events
      ]

      @buffer  = Hash.new { |h, k| h[k] = BufferedTokenizer.new }
      @file    = Hash.new
      @changed = Hash.new
      @reading = Hash.new
      @stop    = false

      @evict_thread = Thread.new do
        until @stop
          evict
          sleep eviction_interval
        end
        evict true
      end

      @tail_thread = Thread.new do
        until @stop
          if @file.size >= OPEN_FILE_LIMIT
            log.debug 'Sleeping until file descriptors become available...'
            sleep 5
          else
            handle(watch_events.shift)
          end
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
      @evict_thread.kill rescue nil
      @tail_thread.kill  rescue nil
      log.debug 'stopped tail'
      return state
    end

    # Return the internal "cursors" state
    def state
      return @cursors.dup
    end

  private
    attr_reader :watch_events, :tail_events, :eviction_interval, :block_size, :cursors, :file, :buffer, :changed, :reading

    def log ; @logger end

    def open path
      if file.size > OPEN_FILE_LIMIT
        log.fatal 'Absolutely too many open files!'
        raise Errno::EMFILE
      end

      return true unless file[path].nil?
      pos = @cursors.include?(path) ? @cursors[path] : 0
      begin
        file[path] = File.open(path)
        file[path].sysseek pos, IO::SEEK_SET
        @cursors[path] = pos
        @changed[path] = Time.now.to_i
      rescue Errno::EMFILE
        log.debug 'skipping: path=%s (too many open files)' % path.inspect
        return false
      rescue Errno::ENOENT
        log.debug 'skipping: path=%s (file does not exist)' % path.inspect
        return false
      end
      log.trace 'opened: path=%s' % path.inspect
      return true
    end

    def read path, size
      if size.nil?
        log.debug 'Erm, size is nil?'
        return
      end
      @reading[path] = true

      bytes_read = 0
      loop do
        begin
          break if file[path].pos >= size
        rescue NoMethodError
          break unless open(path)
          break if file[path].pos >= size
        end

        begin
          data = file[path].sysread @block_size
          buffer[path].extract(data).each do |line|
            log.trace 'captured: path=%s line=%s' % [ path, line ]
            tail_events.push path: path, line: line
          end
        rescue EOFError, Errno::ENOENT
          # we're done here
        end

        last_pos = @cursors[path]
        @cursors[path] = file[path].pos
        bytes_read += @cursors[path] - last_pos
      end

      log.trace 'read: path=%s size=%s cursor=%s' % [
        path.inspect, size.inspect, @cursors[path].inspect
      ]

      @changed[path] = Time.now.to_i
      @reading.delete path
    end

    def close path
      @reading[path] = true # prevent evict from interrupting
      file.delete(path).close if file.include? path
      @cursors.delete(path)
      @changed.delete(path)
      @reading.delete(path)
      log.debug 'closed: path=%s' % path.inspect
    end

    def evict force=false
      cutoff = Time.now.to_i - eviction_interval
      file.keys.each do |path|
        unless force
          next if @reading[path]
          next unless @changed[path] < cutoff
          next unless file.include? path
        end
        file.delete(path).close
        log.debug 'evicted: path=%s' % path.inspect
      end
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