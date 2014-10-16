require 'logger'
require 'thread'
require 'socket'
require 'pathname'

require_relative 'sash'

module Franz

  # Agg mostly aggregates Tail events by applying the multiline filter, but it
  # also applies the "host" and "type" fields. Basically, it does all the post-
  # processing after we've retreived a line from a file.
  class Agg
    @@host = Socket.gethostname # We'll apply the hostname to all events

    attr_reader :seqs

    # Start a new Agg thread in the background.
    #
    # @param [Hash] opts options for the aggregator
    # @option opts [Array<Hash>] :configs ([]) file input configuration
    # @option opts [Queue] :tail_events ([]) "input" queue from Tail
    # @option opts [Queue] :agg_events ([]) "output" queue
    # @option opts [Integer] :flush_interval (5) seconds between flushes
    # @option opts [Hash<Path,Fixnum>] :seqs ({}) internal "seqs" state
    # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
    def initialize opts={}
      @configs     = opts[:configs]     || []
      @tail_events = opts[:tail_events] || []
      @agg_events  = opts[:agg_events]  || []

      @buffer_limit   = opts[:buffer_limit]   || 50
      @flush_interval = opts[:flush_interval] || 10
      @seqs           = opts[:seqs]           || Hash.new
      @logger         = opts[:logger]         || Logger.new(STDOUT)

      @types  = Hash.new
      @lock   = Hash.new { |h,k| h[k] = Mutex.new }
      @buffer = Franz::Sash.new
      @stop   = false

      @t1 = Thread.new do
        until @stop
          flush
          sleep flush_interval
        end
        flush true
      end

      @t2 = Thread.new do
        capture until @stop
      end

      log.debug \
        event: 'agg started',
        configs: @configs,
        tail_events: @tail_events,
        agg_events: @agg_events
    end

    # Stop the Agg thread. Effectively only once.
    #
    # @return [Hash] internal "seqs" state
    def stop
      return state if @stop
      @stop = true
      @t2.kill
      @t1.join
      log.debug event: 'agg stopped'
      return state
    end

    # Return the internal "seqs" state
    def state
      return @seqs.dup
    end

  private
    attr_reader :configs, :tail_events, :agg_events, :flush_interval, :seqs, :types, :lock, :buffer

    def log ; @logger end

    def type path
      begin
        @types.fetch path
      rescue KeyError
        configs.each do |config|
          type = config[:type] if config[:includes].any? { |glob|
            included = File.fnmatch? glob, path
            excludes = !config[:excludes].nil?
            excluded = excludes && config[:excludes].any? { |exlude|
              File.fnmatch? exlude, File::basename(path)
            }
            included && !excluded
          }
          unless type.nil?
            @types[path] = type
            return type
          end
        end
        log.warn \
          event: 'type unknown',
          path: path
        @types[path] = nil
        return nil
      end
    end

    def config path
      t = type(path)
      configs.select { |c| c[:type] == t }.shift
    end

    def seq path
      seqs[path] = seqs.fetch(path, 0) + 1
    end

    def drop? path, message
      drop = config(path)[:drop]
      if drop
        drop = drop.is_a?(Array) ? drop : [ drop ]
        drop.each do |pattern|
          return true if message =~ pattern
        end
      end
      return false
    end

    def enqueue path, message
      if drop? path, message
        log.trace \
          event: 'dropped',
          path: path,
          message: message
        return
      end

      t = type path
      if t.nil?
        log.trace \
          event: 'enqueue skipped',
          path: path,
          message: message
        return
      end

      log.trace \
        event: 'enqueue',
        path: path,
        message: message
      s = seq path
      m = message.encode 'UTF-8', invalid: :replace, undef: :replace, replace: '?'
      agg_events.push path: path, message: m, type: t, host: @@host, '@seq' => s
    end

    def capture
      event = tail_events.shift
      log.trace \
        event: 'capture',
        raw: event
      multiline = config(event[:path])[:multiline] rescue nil
      if multiline.nil?
        enqueue event[:path], event[:line] unless event[:line].empty?
      else
        lock[event[:path]].synchronize do
          size = buffer.size(event[:path])
          if size > @buffer_limit
            log.trace \
              event: 'buffer overflow',
              path: event[:path],
              size: size,
              limmit: @buffer_limit
          end
          if event[:line] =~ multiline
            buffered = buffer.flush(event[:path])
            lines    = buffered.map { |e| e[:line] }.join("\n")
            enqueue event[:path], lines unless lines.empty?
          end
          buffer.insert event[:path], event
        end
      end
    end

    def flush force=false, started=Time.now
      log.debug \
        event: 'flush',
        force: force,
        started: started
      buffer.keys.each do |path|
        lock[path].synchronize do
          if force || started - buffer.mtime(path) >= flush_interval
            buffered = buffer.remove(path)
            lines    = buffered.map { |e| e[:line] }.join("\n")
            enqueue path, lines unless lines.empty?
          end
        end
      end
    end
  end
end