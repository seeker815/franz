require 'pathname'

require 'buftok'


class Franz::Tail
  attr_reader :cursor

  def initialize opts={}, cursor=nil
    @watch_events      = opts[:watch_events]      || []
    @tail_events       = opts[:tail_events]       || []
    @eviction_interval = opts[:eviction_interval] || 5
    @cursor            = cursor                   || Hash.new

    @buffer  = Hash.new { |h, k| h[k] = BufferedTokenizer.new }
    @file    = Hash.new
    @changed = Hash.new
    @reading = Hash.new

    @block_size = 5120 # 5 KiB
    @stop = false

    @t1 = Thread.new do
      until @stop
        evict
        sleep eviction_interval
      end
      sleep eviction_interval
      evict
    end

    @t2 = Thread.new do
      until @stop
        e = watch_events.shift
        case e[:name]
        when :created
        when :replaced
          close e[:path]
          read e[:path], e[:size], e[:type]
        when :truncated
          close e[:path]
          read e[:path], e[:size], e[:type]
        when :appended
          read e[:path], e[:size], e[:type]
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
    @t2.kill
    @t1.join
    return @cursor
  end

private
  attr_reader :watch_events, :tail_events, :eviction_interval, :file, :buffer

  def realpath path
    Pathname.new(path).realpath.to_s
  end

  def open path
    return true unless file[path].nil?
    pos = @cursor.include?(path) ? @cursor[path] : 0
    begin
      file[path] = File.open(path)
      file[path].sysseek pos, IO::SEEK_SET
      @cursor[path] = pos
      @changed[path] = Time.now.to_i
    rescue Errno::ENOENT
      return false
    end
    return true
  end

  def read path, size, type
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
          tail_events.push type: type, path: realpath(path), line: line
        end
      rescue EOFError, Errno::ENOENT
        # we're done here
      end
      @cursor[path] = file[path].pos
    end

    @changed[path] = Time.now.to_i
    @reading.delete path
  end

  def close path
    @reading[path] = true # prevent evict from interrupting
    file.delete(path).close if file.include? path
    @cursor.delete(path)
    @changed.delete(path)
    @reading.delete(path)
  end

  def evict
    file.keys.each do |path|
      next if @reading[path]
      next unless @changed[path] < Time.now.to_i - eviction_interval
      next unless file.include? path
      file.delete(path).close
    end
  end
end