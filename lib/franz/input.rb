require 'logger'

require 'deep_merge'

require_relative 'agg'
require_relative 'tail'
require_relative 'watch'
require_relative 'discover'
require_relative 'queue'

module Franz

  # File input for Franz. Really, the only input for Franz, so I hope you like it.
  class Input
    # Start a new input in the background. We'll generate a stream of events by
    # watching the filesystem for changes (Franz::Discover and Franz::Watch),
    # tailing files (Franz::Tail), and generating events (Franz::Agg)
    #
    # @param [Hash] opts options for the aggregator
    # @option opts [Hash] :input ({}) "input" configuration
    # @option opts [Queue] :output (Queue.new) "output" queue
    # @option opts [Hash<Path,State>] :state ({}) internal state
    # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
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
        discover_interval: opts[:input][:discover_interval],
        ignore_before: opts[:input][:ignore_before],
        logger: opts[:logger],
        known: known

      @watch = Franz::Watch.new \
        discoveries: discoveries,
        deletions: deletions,
        watch_events: watch_events,
        watch_interval: opts[:input][:watch_interval],
        logger: opts[:logger],
        stats: stats

      @tail = Franz::Tail.new \
        watch_events: watch_events,
        tail_events: tail_events,
        eviction_interval: opts[:input][:eviction_interval],
        logger: opts[:logger],
        cursors: cursors

      @agg = Franz::Agg.new \
        configs: opts[:input][:configs],
        tail_events: tail_events,
        agg_events: opts[:output],
        flush_interval: opts[:input][:flush_interval],
        logger: opts[:logger],
        seqs: seqs
    end

    # Stop everything. Has the effect of draining all the Queues and waiting on
    # auxilliarly threads (e.g. eviction) to complete full intervals, so it may
    # ordinarily take tens of seconds, depends on your configuration.
    #
    # @return [Hash] compact internal state
    def stop
      stats   = @watch.stop rescue {}
      cursors = @tail.stop  rescue {}
      seqs    = @agg.stop   rescue {}
      stats.keys.each do |path|
        stats[path][:cursor] = cursors[path] rescue nil
        stats[path][:seq]    = seqs[path]    rescue nil
      end
      return stats
    end
  end
end