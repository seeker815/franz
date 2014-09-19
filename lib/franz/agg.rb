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

      @flush_interval = opts[:flush_interval] || 10
      @seqs           = opts[:seqs]           || Hash.new
      @logger         = opts[:logger]         || Logger.new(STDOUT)

      @types  = Hash.new
      @lock   = Hash.new { |h,k| h[k] = Mutex.new }
      @buffer = Franz::Sash.new
      @stop   = false

      @num_events = 0

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
          event: 'agg type() failed',
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

    def enqueue path, message
      t = type path
      return if t.nil?
      s = seq path
      m = message.encode 'UTF-8', invalid: :replace, undef: :replace, replace: '?'
      agg_events.push path: path, message: m, type: t, host: @@host, '@seq' => s
      @num_events += 1
    end

    def capture
      buffer_size = buffer.keys.size
      tail_events_size = tail_events.size
      agg_events_size  = agg_events.size
      cp_started = Time.now

      event = tail_events.shift
      cp_dequeued = Time.now

      multiline = config(event[:path])[:multiline] rescue nil
      enqueued = false
      if multiline.nil?
        enqueue event[:path], event[:line] unless event[:line].empty?
        enqueued = true
      else
        lock[event[:path]].synchronize do
          if event[:line] =~ multiline
            buffered = buffer.flush(event[:path])
            lines    = buffered.map { |e| e[:line] }.join("\n")
            enqueue event[:path], lines unless lines.empty?
            enqueued = true
          end
          buffer.insert event[:path], event
        end
      end
      cp_captured = Time.now

      elapsed_total      = cp_captured - cp_started
      elapsed_in_dequeue = cp_dequeued - cp_started
      elapsed_in_capture = cp_captured - cp_dequeued
      log.trace \
        event: 'agg finished',
        path: event[:path],
        enqueued: enqueued,
        elapsed_total: elapsed_total,
        elapsed_in_dequeue: elapsed_in_dequeue,
        elapsed_in_capture: elapsed_in_capture,
        tail_events_size_before: tail_events_size,
        agg_events_size_before: agg_events_size,
        tail_events_size_after: tail_events.size,
        agg_events_size_after: agg_events.size,
        buffer_size_before: buffer_size,
        buffer_size_after: buffer.keys.size,
        num_events: @num_events
    end

    def flush force=false
      tail_events_size = tail_events.size
      agg_events_size  = agg_events.size
      started = Time.now
      keys = buffer.keys
      buffer_size = keys.size
      keys.each do |path|
        lock[path].synchronize do
          if started - buffer.mtime(path) >= flush_interval || force
            log.trace \
              event: 'agg flush',
              path: path
            buffered = buffer.remove(path)
            lines    = buffered.map { |e| e[:line] }.join("\n")
            enqueue path, lines unless lines.empty?
          end
        end
      end
      elapsed = Time.now - started
      log.trace \
        event: 'agg flush finished',
        elasped: elapsed,
        tail_events_size_before: tail_events_size,
        agg_events_size_before: agg_events_size,
        tail_events_size_after: tail_events.size,
        agg_events_size_after: agg_events.size,
        buffer_size_before: buffer_size,
        buffer_size_after: buffer.keys.size
    end
  end
end