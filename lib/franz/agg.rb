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
    # @option opts [Queue] :tail_events (Queue.new) "input" queue from Tail
    # @option opts [Queue] :agg_events (Queue.new) "output" queue
    # @option opts [Integer] :flush_interval (5) seconds between flushes
    # @option opts [Hash<Path,Fixnum>] :seqs ({}) internal "seqs" state
    # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
    def initialize opts={}
      @configs        = opts[:configs]        || Array.new
      @tail_events    = opts[:tail_events]    || Queue.new
      @agg_events     = opts[:agg_events]     || Queue.new
      @flush_interval = opts[:flush_interval] || 5
      @seqs           = opts[:seqs]           || Hash.new
      @logger         = opts[:logger]         || Logger.new(STDOUT)

      @types  = Hash.new
      @lock   = Mutex.new
      @buffer = Franz::Sash.new
      @stop   = false

      @t1 = Thread.new do
        until @stop
          flush
          sleep flush_interval
        end
        sleep flush_interval
        flush
      end

      @t2 = Thread.new do
        until @stop
          capture
        end
      end
    end

    # Stop the Agg thread. Effectively only once.
    #
    # @return [Hash] internal "seqs" state
    def stop
      return @seqs if @stop
      @stop = true
      @t2.kill
      @t1.join
      return @seqs
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
            excluded = config[:excludes].any? { |exlude_glob|
              File.fnmatch? exlude_glob, path
            }
            included && !excluded
          }
          return @types[path] = type unless type.nil?
        end
        raise 'Could not identify type for path=%s' % path
      end
    end

    def config path
      # log.debug 'config path=%s' % path.inspect
      configs.select { |c| c[:type] == type(path) }.shift
    end

    def seq path
      # log.debug 'seq path=%s' % path.inspect
      seqs[path] = seqs.fetch(path, 0) + 1
    end

    def real_path path
      Pathname.new(path).realpath.to_s
    end

    def enqueue path, message
      p = real_path path
      t = type path
      s = seq p
      m = message.encode 'UTF-8', invalid: :replace, undef: :replace, replace: '?'
      # log.debug 'enqueue type=%s path=%s seq=%d message=%s' % [
      #   t.inspect, p.inspect, s.inspect, m.inspect
      # ]
      agg_events.push path: p, message: m, type: t, seq: s, host: @@host
    end

    def capture
      event     = tail_events.shift
      # log.debug 'received path=%s line=%s' % [
      #   event[:path], event[:line]
      # ]
      multiline = config(event[:path])[:multiline]
      if multiline.nil?
        enqueue event[:path], event[:line]
      else
        lock.synchronize do
          if event[:line] =~ multiline
            buffered = buffer.flush(event[:path])
            lines = buffered.map { |e| e[:line] }
            unless lines.empty?
              enqueue event[:path], lines.join("\n")
            end
          end
          buffer.insert event[:path], event
        end
      end
    end

    def flush
      lock.synchronize do
        started = Time.now
        buffer.keys.each do |path|
          if started - buffer.mtime(path) >= flush_interval
            # log.debug 'flushing path=%s' % path.inspect
            buffered = buffer.remove(path)
            lines = buffered.map { |e| e[:line] }
            unless lines.empty?
              enqueue path, lines.join("\n")
            end
          end
        end
      end
    end
  end
end