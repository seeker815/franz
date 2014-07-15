require_relative 'discover'
require_relative 'watch'
require_relative 'tail'
require_relative 'multiline'
require_relative 'bounded_queue'


class Franz::Input
  def initialize opts={}
    opts = {
      output: nil,
      configs: [],
      discover_interval: nil,
      watch_interval: nil,
      discover_bound: 4096,
      watch_bound: 4096,
      tail_bound: 4096,
      state: {}
    }.merge(opts)

    known = opts[:state].keys
    stats, cursors, seqs = {}, {}, {}
    known.each do |path|
      cursor        = opts[:state][path].delete :cursor
      seq           = opts[:state][path].delete :seq
      cursors[path] = cursor unless cursor.nil?
      seqs[path]    = seq    unless seq.nil?
      stats[path]   = opts[:state][path]
    end

    discoveries  = Franz::BoundedQueue.new opts[:discover_bound]
    deletions    = Franz::BoundedQueue.new opts[:discover_bound]
    watch_events = Franz::BoundedQueue.new opts[:watch_bound]
    tail_events  = Franz::BoundedQueue.new opts[:tail_bound]

    @d = Franz::Discover.new \
      discoveries: discoveries,
      deletions: deletions,
      configs: opts[:configs],
      interval: opts[:discover_interval],
      known: known

    @w = Franz::Watch.new \
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events,
      interval: opts[:watch_interval],
      stats: stats

    @t = Franz::Tail.new \
      watch_events: watch_events,
      tail_events: tail_events,
      cursors: cursors

    @m = Franz::Multiline.new \
      configs: opts[:configs],
      tail_events: tail_events,
      multiline_events: opts[:output],
      seqs: seqs
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