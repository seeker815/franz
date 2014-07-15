require_relative 'helpers'


class Franz::Watch
  include Franz::Helpers

  attr_reader :stats

  def initialize opts={}, stats=nil
    @discoveries  = opts[:discoveries]  || []
    @deletions    = opts[:deletions]    || []
    @watch_events = opts[:watch_events] || []
    @interval     = opts[:interval]     || 1
    @stats        = stats               || Hash.new

    @stop = false

    # Need to resend old events to make sure Tail catches up
    stats.each do |path, old_stat|
      watch_events.push name: :appended, path: path, size: old_stat[:size]
    end

    @t = Thread.new do
      until @stop
        until discoveries.empty?
          @stats[discoveries.pop] = nil
        end
        watch.each do |deleted|
          @stats.delete deleted
          deletions.push deleted
        end
        sleep interval
      end
    end
  end

  def stop
    @stop = true
    @t.join
    return @stats
  end

private
  attr_reader :discoveries, :deletions, :watch_events, :interval, :stats

  def enqueue name, path, size=nil
    watch_events.push name: name, path: path, size: size
  end

  def watch
    
    deleted = []
    stats.each do |path, old_stat|
      stat = stat_for path
      stats[path] = stat

      if file_created? old_stat, stat
        enqueue :created, path
      elsif file_deleted? old_stat, stat
        enqueue :deleted, path
        deleted.push path # deal with this below
      end

      if file_replaced? old_stat, stat
        enqueue :replaced, path, stat[:size]
      elsif file_appended? old_stat, stat
        enqueue :appended, path, stat[:size]
      elsif file_truncated? old_stat, stat
        enqueue :truncated, path, stat[:size]
      end
    end
    return deleted
  end
end