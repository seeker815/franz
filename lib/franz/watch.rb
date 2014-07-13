require_relative 'helpers'


class Watch
  include Franz::Helpers

  def initialize opts={}
    @discoveries  = opts[:discoveries]  || []
    @deletions    = opts[:deletions]    || []
    @watch_events = opts[:watch_events] || []
    @interval     = opts[:interval]     || 1

    @stats, @types = {}, {}

    Thread.new do
      loop do
        until discoveries.empty?
          d = discoveries.pop
          types[d[:path]] = d[:type]
          stats[d[:path]] = nil
        end
        watch.each do |deleted|
          stats.delete deleted
          deletions.push deleted
        end
        sleep interval
      end
    end
  end

private
  attr_reader :discoveries, :deletions, :watch_events, :interval, :stats, :types

  def enqueue name, type, path, stat
    stat = name == :created ? nil : stat
    watch_events.push name: name, type: type, path: path, stat: stat
  end

  def watch
    deleted = []
    stats.each do |path, old_stat|
      stat = stat_for path
      stats[path] = stat

      if file_created? old_stat, stat
        enqueue :created, types[path], path, stat
      elsif file_deleted? old_stat, stat
        enqueue :deleted, types[path], path, stat
        deleted.push path # deal with this below
      end

      if file_replaced? old_stat, stat
        enqueue :replaced, types[path], path, stat
      elsif file_appended? old_stat, stat
        enqueue :appended, types[path], path, stat
      elsif file_truncated? old_stat, stat
        enqueue :truncated, types[path], path, stat
      end
    end
    return deleted
  end
end