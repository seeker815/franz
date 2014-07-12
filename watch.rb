require_relative './object_builder'
require_relative './file_helpers'

Thread.abort_on_exception = true

Watch = Object.new
Watch.extend FileHelpers

Object(Watch) { |o|

  o.new = ->(opts) {
    @discoveries  = opts[:discoveries]  || []
    @deletions    = opts[:deletions]    || []
    @watch_events = opts[:watch_events] || []
    @interval     = opts[:interval]         || 1

    @stats, @types = {}, {}

    Thread.new do
      loop do
        until discoveries.empty?
          d = discoveries.pop 
          stats[d[:path]] = nil
          types[d[:path]] = d[:type]
        end
        watch.each do |deleted|
          stats.delete deleted
          deletions.push deleted
        end
        sleep interval
      end
    end
  }

private
  attr_reader :discoveries, :deletions, :watch_events, :interval, :stats, :types

  o.enqueue = ->(name, type, path, old_stat, new_stat) {
    norm_stat = name == :created ? nil : new_stat
    watch_events.push name: name, type: type, path: path, old_stat: old_stat, new_stat: norm_stat
  }

  o.watch = -> {
    deleted = []
    stats.each do |path, old_stat|
      new_stat = stat_for path
      stats[path] = new_stat

      if file_created? old_stat, new_stat
        enqueue :created, types[path], path, old_stat, new_stat
      elsif file_deleted? old_stat, new_stat
        enqueue :deleted, types[path], path, old_stat, new_stat
        deleted.push path # deal with this below
      end

      if file_replaced? old_stat, new_stat
        enqueue :replaced, types[path], path, old_stat, new_stat
      elsif file_appended? old_stat, new_stat
        enqueue :appended, types[path], path, old_stat, new_stat
      elsif file_truncated? old_stat, new_stat
        enqueue :truncated, types[path], path, old_stat, new_stat
      end
    end
    return deleted
  }
}