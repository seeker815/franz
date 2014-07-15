require 'thread'

require_relative 'discover'
require_relative 'watch'
require_relative 'tail'
require_relative 'multiline'
require_relative 'bounded_queue'


class Franz::Input
  def initialize opts={}, state=nil
    opts = {
      queue: Queue.new,
      configs: [],
      discover_interval: nil,
      watch_interval: nil
    }.merge(opts)

    state ||= {}
    known   = state.keys
    stats, cursors, seqs = {}, {}, {}
    known.each do |path|
      cursor        = state[path].delete :cursor
      seq           = state[path].delete :seq
      cursors[path] = cursor unless cursor.nil?
      seqs[path]    = seq    unless seq.nil?
      stats[path]   = state[path]
    end

    discoveries  = Franz::BoundedQueue.new 4096
    deletions    = Franz::BoundedQueue.new 4096
    watch_events = Franz::BoundedQueue.new 4096
    tail_events  = Franz::BoundedQueue.new 4096

    @d = Franz::Discover.new({
      discoveries: discoveries,
      deletions: deletions,
      configs: opts[:configs],
      interval: opts[:discover_interval]
    }, known)

    @w = Franz::Watch.new({
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events,
      interval: opts[:watch_interval]
    }, stats)

    @t = Franz::Tail.new({
      watch_events: watch_events,
      tail_events: tail_events
    }, cursors)

    @m = Franz::Multiline.new({
      configs: opts[:configs],
      tail_events: tail_events,
      multiline_events: opts[:queue]
    }, seqs)
  end

  def stop
    stats   = @w.stop rescue {}
    cursors = @t.stop rescue {}
    seqs    = @m.stop rescue {}
    stats.keys.each do |path|
      stats[path][:cursor] = cursors[path] rescue nil
      stats[path][:seq]    = seqs[path]    rescue nil
    end
    return stats
  end
end