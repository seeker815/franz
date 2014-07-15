require 'thread'

require_relative 'sash'


class Franz::Multiline
  attr_reader :seqs

  def initialize opts={}, seqs=nil
    @configs          = opts[:configs]          || []
    @tail_events      = opts[:tail_events]      || []
    @multiline_events = opts[:multiline_events] || []
    @flush_interval   = opts[:flush_interval]   || 5
    @seqs             = opts[:seqs]              || Hash.new

    @type   = Hash.new
    @lock   = Mutex.new
    @buffer = Sash.new

    @stop = false

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

  def stop
    @stop = true
    @t2.kill
    @t1.join
    return @seqs
  end

private
  attr_reader :configs, :tail_events, :multiline_events, :flush_interval, :lock, :buffer, :seqs

  def type path
    begin
      @type.fetch path
    rescue KeyError
      configs.each do |config|
        type = config[:type] if config[:includes].any? { |glob|
          File.fnmatch?(glob, path) && !config[:excludes].any? { |xglob|
            File.fnmatch?(xglob, path)
          }
        }
        return @type[path] = type unless type.nil?
      end
      raise 'Could not identify type for path=%s' % path
    end
  end

  def config path
    configs.select { |c| c[:type] == type(path) }.shift
  end

  def enqueue path, message
    begin
      seq = seqs.fetch(path)
    rescue KeyError
      seq, seqs[path] = 1, 1
    end
    multiline_events.push type: type(path), path: path, message: message, seq: seq
  end

  def capture 
    event     = tail_events.shift
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