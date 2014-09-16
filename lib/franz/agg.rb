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

      log.debug 'agg: configs=%s tail_events=%s agg_events=%s' % [
        @configs, @tail_events, @agg_events
      ]

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

      log.debug 'started agg'
    end

    # Stop the Agg thread. Effectively only once.
    #
    # @return [Hash] internal "seqs" state
    def stop
      return state if @stop
      @stop = true
      @t2.kill
      @t1.join
      log.debug 'stopped agg'
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
          return @types[path] = type unless type.nil?
        end
        log.error 'Could not identify type for path=%s' % path
        @types[path] = nil
      end
    end

    def config path
      t = type(path)
      configs.select { |c| c[:type] == t }.shift
    end

    def seq path
      seqs[path] = seqs.fetch(path, 0) + 1
    end

    def real_path path
      Pathname.new(path).realpath.to_s rescue path
    end

    def enqueue path, message
      started = Time.now
      p = real_path path
      t = type path
      return if t.nil?
      s = seq path
      m = message.encode 'UTF-8', invalid: :replace, undef: :replace, replace: '?'
      log.trace 'enqueue type=%s path=%s seq=%d message=%s' % [
        t.inspect, p.inspect, s.inspect, m.inspect
      ]
      agg_events.push path: p, message: m, type: t, host: @@host, '@seq' => s
      elapsed = Time.now - started
      log.debug 'enqueued elapsed=%fs' % elapsed
    end

    def capture
      event = tail_events.shift
      log.trace 'received path=%s line=%s' % [
        event[:path], event[:line]
      ]
      multiline = config(event[:path])[:multiline] rescue nil
      if multiline.nil?
        enqueue event[:path], event[:line] unless event[:line].empty?
      else
        lock[event[:path]].synchronize do
          if event[:line] =~ multiline
            buffered = buffer.flush(event[:path])
            lines    = buffered.map { |e| e[:line] }.join("\n")
            enqueue event[:path], lines unless lines.empty?
          end
          buffer.insert event[:path], event
        end
      end
    end

    def flush force=false
      started = Time.now
      buffer.keys.each do |path|
        lock[path].synchronize do
          if started - buffer.mtime(path) >= flush_interval || force
            log.trace 'flushing path=%s' % path.inspect
            buffered = buffer.remove(path)
            lines    = buffered.map { |e| e[:line] }.join("\n")
            enqueue path, lines unless lines.empty?
          end
        end
      end
      elapsed = Time.now - started
      log.debug 'flushed elapsed=%fs' % elapsed
    end
  end
end