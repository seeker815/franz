require 'buftok'

Thread.abort_on_exception = true

class Tail
  def initialize opts={}
    @watch_events      = opts[:watch_events]      || []
    @tail_events       = opts[:tail_events]       || []
    @eviction_interval = opts[:eviction_interval] || 5

    @file   = Hash.new
    @status = Hash.new
    @buffer = Hash.new { |h, k| h[k] = BufferedTokenizer.new }

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
          close e
          read e
        when :truncated
          close e
          read e
        when :appended
          read e
        when :deleted
          close e
        else
          raise 'Invalid watch event'
        end
      end
    end

    return self
  end

private
  attr_reader :watch_events, :tail_events, :eviction_interval, :file, :status, :buffer

  def open event
    pos = status.include?(event[:path]) ? status[event[:path]][:pos] : 0
    file[event[:path]] = File.open(event[:path])
    file[event[:path]].sysseek pos, IO::SEEK_SET
    status[event[:path]] = { changed: Time.now.to_i, pos: pos }
  end

  def read event
    open event if file[event[:path]].nil?
    until file[event[:path]].pos >= event[:new_stat][:size]
      begin
        data = file[event[:path]].sysread(1048576) # 1 MiB
        status[event[:path]] = { changed: Time.now.to_i, pos: file[event[:path]].pos }
        buffer[event[:path]].extract(data).each do |line|
          tail_events.push type: event[:type], path: event[:path], line: line
        end
      rescue EOFError
        # we're done here
      end
    end
  end

  def close event
    file.delete(event[:path]).close
    status.delete(event[:path])
  end

  def evict
    status.keys.each do |path|
      next unless status[path][:changed] < Time.now.to_i - eviction_interval
      next unless file.include? path
      file.delete(path).close
    end
  end
end