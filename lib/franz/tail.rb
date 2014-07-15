require 'logger'
require 'pathname'

require 'buftok'


class Franz::Tail
  attr_reader :cursors

  def initialize opts={}
    @watch_events      = opts[:watch_events]      || []
    @tail_events       = opts[:tail_events]       || []
    @eviction_interval = opts[:eviction_interval] || 5
    @block_size        = opts[:block_size]        || 5120 # 5 KiB
    @cursors           = opts[:cursors]           || Hash.new
    @logger            = opts[:logger]            || Logger.new(STDOUT)

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
      sleep eviction_interval
      evict
    end

    @watch_thread = Thread.new do
      until @stop
        e = watch_events.shift
        case e[:name]
        when :created
        when :replaced
          close e[:path]
          read e[:path], e[:size]
        when :truncated
          close e[:path]
          read e[:path], e[:size]
        when :appended
          read e[:path], e[:size]
        when :deleted
          close e[:path]
        else
          raise 'Invalid watch event'
        end
      end
    end
  end

  def stop
    @stop = true
    @watch_thread.kill
    @evict_thread.join
    return @cursors
  end

private
  attr_reader :watch_events, :tail_events, :eviction_interval, :block_size, :cursors, :file, :buffer, :changed, :reading

  def log ; @logger end

  def realpath path
    Pathname.new(path).realpath.to_s
  end

  def open path
    return true unless file[path].nil?
    pos = @cursors.include?(path) ? @cursors[path] : 0
    begin
      file[path] = File.open(path)
      file[path].sysseek pos, IO::SEEK_SET
      @cursors[path] = pos
      @changed[path] = Time.now.to_i
    rescue Errno::ENOENT
      return false
    end
    log.debug 'opened: path=%s' % path.inspect
    return true
  end

  def read path, size
    @reading[path] = true

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
          tail_events.push path: realpath(path), line: line
        end
      rescue EOFError, Errno::ENOENT
        # we're done here
      end
      @cursors[path] = file[path].pos
    end

    log.debug 'read: path=%s size=%s' % [ path.inspect, size.inspect ]
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

  def evict
    file.keys.each do |path|
      next if @reading[path]
      next unless @changed[path] < Time.now.to_i - eviction_interval
      next unless file.include? path
      file.delete(path).close
      log.debug 'evicted: path=%s' % path.inspect
    end
  end
end