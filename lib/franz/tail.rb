require 'pathname'

require 'buftok'


class Franz::Tail
  def initialize opts={}
    @watch_events      = opts[:watch_events]      || []
    @tail_events       = opts[:tail_events]       || []
    @eviction_interval = opts[:eviction_interval] || 5

    @file    = Hash.new
    @buffer  = Hash.new { |h, k| h[k] = BufferedTokenizer.new }
    @cursor  = Hash.new
    @changed = Hash.new
    @reading = Hash.new

    @block_size = 1024 # 1 KiB

    Thread.new do
      loop do
        evict
        sleep eviction_interval
      end
    end

    Thread.new do
      loop do
        e = watch_events.shift
        case e[:name]
        when :created
        when :replaced
          close e[:path]
          read e[:path], e[:stat][:size], e[:type]
        when :truncated
          close e[:path]
          read e[:path], e[:stat][:size], e[:type]
        when :appended
          read e[:path], e[:stat][:size], e[:type]
        when :deleted
          close e[:path]
        else
          raise 'Invalid watch event'
        end
      end
    end
  end

private
  attr_reader :watch_events, :tail_events, :eviction_interval, :file, :buffer

  def realpath path
    Pathname.new(path).realpath.to_s
  end

  def open path
    pos = @cursor.include?(path) ? @cursor[path] : 0
    file[path] = File.open(path)
    file[path].sysseek pos, IO::SEEK_SET
    @cursor[path] = pos
    @changed[path] = Time.now.to_i
  end

  def read path, size, type
    open path if file[path].nil?
    @reading[path] = true
    until file[path].pos >= size
      begin
        data = file[path].sysread @block_size
        buffer[path].extract(data).each do |line|
          tail_events.push type: type, path: realpath(path), line: line
        end
      rescue EOFError
        # we're done here
      end
    end
    @cursor[path] = file[path].pos
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