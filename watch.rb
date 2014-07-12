require_relative './object_builder'
require_relative './file_helpers'

Thread.abort_on_exception = true

Watch = Object.new
Watch.extend FileHelpers

Object(Watch) { |o|

  o.new = ->(opts) {
    discoveries  = opts[:discoveries]  || []
    deletions    = opts[:deletions]    || []
    watch_events = opts[:watch_events] || []
    rest         = opts[:rest]         || 1
    Thread.new do
      stats, types = {}, {}
      loop do
        until discoveries.empty?
          path, type = discoveries.pop
          stats[path] = nil
          types[path] = type
        end
        stats = watch stats, types, discoveries, deletions, watch_events
        sleep rest
      end
    end
  }

private
  o.enqueue = ->(q, name, type, path, old_stat, new_stat) {
    norm_stat = name == :created ? nil : new_stat
    q.push name: name, type: type, path: path, old_stat: old_stat, new_stat: norm_stat
  }

  o.watch = ->(stats, types, discoveries, deletions, q) {
    deleted = []
    stats.each do |path, old_stat|
      new_stat = stat_for path
      stats[path] = new_stat

      if file_created? old_stat, new_stat
        enqueue q, :created, types[path], path, old_stat, new_stat
      elsif file_deleted? old_stat, new_stat
        enqueue q, :deleted, types[path], path, old_stat, new_stat
        deleted.push path # deal with this below
      end

      if file_replaced? old_stat, new_stat
        enqueue q, :replaced, types[path], path, old_stat, new_stat
      elsif file_appended? old_stat, new_stat
        enqueue q, :appended, types[path], path, old_stat, new_stat
      elsif file_truncated? old_stat, new_stat
        enqueue q, :truncated, types[path], path, old_stat, new_stat
      end
    end

    deleted.each do |path|
      stats.delete path
      deletions.push path
    end
    return stats
  }
}