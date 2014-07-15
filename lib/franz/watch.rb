require 'logger'

require_relative 'helpers'


class Franz::Watch
  include Franz::Helpers

  def initialize opts={}
    @discoveries  = opts[:discoveries]  || []
    @deletions    = opts[:deletions]    || []
    @watch_events = opts[:watch_events] || []
    @interval     = opts[:interval]     || 1
    @stats        = opts[:stats]        || Hash.new
    @logger       = opts[:logger]       || Logger.new(STDOUT)

    # Need to resend old events to make sure Tail catches up
    stats.each do |path, old_stat|
      watch_events.push name: :appended, path: path, size: old_stat[:size]
    end

    @stop = false

    @thread = Thread.new do
      until @stop
        until discoveries.empty?
          d = discoveries.pop
          @stats[d] = nil
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
    @thread.join
    return @stats
  end

private
  attr_reader :discoveries, :deletions, :watch_events, :interval, :stats

  def log ; @logger end

  def enqueue name, path, size=nil
    log.debug 'enqueue: name=%s path=%s size=%s' % [
      name.inspect, path.inspect, size.inspect
    ]
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
        deleted << path
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