require 'logger'
require 'thread'
require 'socket'
require 'pathname'

require_relative 'sash'
require_relative 'stats'
require_relative 'input_config'

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
    # @option opts [InputConfig] :input_config shared Franz configuration
    # @option opts [Queue] :tail_events ([]) "input" queue from Tail
    # @option opts [Queue] :agg_events ([]) "output" queue
    # @option opts [Integer] :flush_interval (5) seconds between flushes
    # @option opts [Hash<Path,Fixnum>] :seqs ({}) internal "seqs" state
    # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
    def initialize opts={}
      @ic = opts[:input_config] || raise('No input_config specified')

      @tail_events = opts[:tail_events] || []
      @agg_events  = opts[:agg_events]  || []

      @buffer_limit   = opts[:buffer_limit]   || 50
      @flush_interval = opts[:flush_interval] || 10
      @seqs           = opts[:seqs]           || Hash.new
      @logger         = opts[:logger]         || Logger.new(STDOUT)

      @lock   = Hash.new { |h,k| h[k] = Mutex.new }
      @buffer = Franz::Sash.new
      @stop   = false

      @statz = opts[:statz] || Franz::Stats.new
      @statz.create :num_lines, 0

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
    attr_reader :tail_events, :agg_events, :flush_interval, :lock, :buffer

    def log ; @logger end

    def seq path
      seqs[path] = seqs.fetch(path, 0) + 1
    end

    def enqueue path, message
      if @ic.drop? path, message
        log.trace \
          event: 'dropped',
          path: path,
          message: message
        return
      end

      t = @ic.type path
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

      event = { type: t, host: @@host, '@seq' => s }

      if @ic.json? path
        return if m =~ /^#/
        event = JSON::parse(m).merge(event)
      else
        event.merge! message: m, path: path
      end
      agg_events.push event
    end

    def capture
      event = tail_events.shift
      log.trace \
        event: 'capture',
        raw: event
      multiline = @ic.config(event[:path])[:multiline] rescue nil
      if multiline.nil?
        @statz.inc :num_lines
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
            lines    = buffered.map { |e| e[:line] }
            @statz.inc :num_lines, lines.length
            lines    = lines.join("\n")
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
            lines    = buffered.map { |e| e[:line] }
            @statz.inc :num_lines, lines.length
            lines    = lines.join("\n")
            enqueue path, lines unless lines.empty?
          end
        end
      end
    end
  end
end