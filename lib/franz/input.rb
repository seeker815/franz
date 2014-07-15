require 'logger'

require 'deep_merge'

require_relative 'tail'
require_relative 'watch'
require_relative 'discover'
require_relative 'multiline'
require_relative 'queue'


class Franz::Input
  def initialize opts={}
    opts = {
      logger: Logger.new(STDOUT),
      state: nil,
      output: nil,
      input: {
        discover_bound: 4096,
        watch_bound: 4096,
        tail_bound: 4096,
        discover_interval: nil,
        watch_interval: nil,
        eviction_interval: nil,
        flush_interval: nil,
        configs: []
      }
    }.deep_merge!(opts)

    state = opts[:state] || {}
    known = state.keys
    stats, cursors, seqs = {}, {}, {}
    known.each do |path|
      cursor        = state[path].delete :cursor
      seq           = state[path].delete :seq
      cursors[path] = cursor unless cursor.nil?
      seqs[path]    = seq    unless seq.nil?
      stats[path]   = state[path]
    end

    discoveries  = Franz::Queue.new opts[:input][:discover_bound]
    deletions    = Franz::Queue.new opts[:input][:discover_bound]
    watch_events = Franz::Queue.new opts[:input][:watch_bound]
    tail_events  = Franz::Queue.new opts[:input][:tail_bound]

    Franz::Discover.new \
      discoveries: discoveries,
      deletions: deletions,
      configs: opts[:input][:configs],
      interval: opts[:input][:discover_interval],
      logger: opts[:logger],
      known: known

    @watch = Franz::Watch.new \
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events,
      interval: opts[:input][:watch_interval],
      logger: opts[:logger],
      stats: stats

    @tail = Franz::Tail.new \
      watch_events: watch_events,
      tail_events: tail_events,
      eviction_interval: opts[:input][:eviction_interval],
      logger: opts[:logger],
      cursors: cursors

    @multiline = Franz::Multiline.new \
      configs: opts[:input][:configs],
      tail_events: tail_events,
      multiline_events: opts[:output],
      flush_interval: opts[:input][:flush_interval],
      logger: opts[:logger],
      seqs: seqs
  end

  def stop
    stats   = @watch.stop     rescue {}
    cursors = @tail.stop      rescue {}
    seqs    = @multiline.stop rescue {}
    stats.keys.each do |path|
      stats[path][:cursor] = cursors[path] rescue nil
      stats[path][:seq]    = seqs[path]    rescue nil
    end
    return stats
  end
end