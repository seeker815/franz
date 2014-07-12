require_relative './object_builder'
require_relative './file_helpers'

Thread.abort_on_exception = true

Watch = Object.new
Watch.extend FileHelpers

Object(Watch) { |o|

  o.new = ->(opts) {
    discoveries = opts[:discoveries] || []
    deletions   = opts[:deletions]   || []
    events      = opts[:events]      || []
    rest        = opts[:rest]        || 1
    Thread.new do
      stats = {}
      loop do
        stats[discoveries.pop] = nil until discoveries.empty?
        stats = watch stats, discoveries, deletions, events
        sleep rest
      end
    end
  }

private
  o.enqueue = ->(q, event, path, old_stat, new_stat) {
    norm_stat = event == :created ? nil : new_stat
    q.push event: event, path: path, old_stat: old_stat, new_stat: norm_stat
  }

  o.watch = ->(stats, discoveries, deletions, events) {
    deleted = []
    stats.each do |path, old_stat|
      new_stat = stat_for path
      stats[path] = new_stat

      if file_created? old_stat, new_stat
        enqueue events, :created, path, old_stat, new_stat
      elsif file_deleted? old_stat, new_stat
        enqueue events, :deleted, path, old_stat, new_stat
        deleted.push path # deal with this below
      end

      if file_replaced? old_stat, new_stat
        enqueue events, :replaced, path, old_stat, new_stat
      elsif file_appended? old_stat, new_stat
        enqueue events, :appended, path, old_stat, new_stat
      elsif file_truncated? old_stat, new_stat
        enqueue events, :truncated, path, old_stat, new_stat
      end
    end

    deleted.each do |path|
      stats.delete path
      deletions.push path
    end
    return stats
  }
}