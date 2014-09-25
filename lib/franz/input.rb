require 'logger'
require 'fileutils'

require 'deep_merge'

require_relative 'agg'
require_relative 'tail'
require_relative 'watch'
require_relative 'discover'

module Franz

  # File input for Franz. Really, the only input for Franz, so I hope you like it.
  class Input
    # Start a new input in the background. We'll generate a stream of events by
    # watching the filesystem for changes (Franz::Discover and Franz::Watch),
    # tailing files (Franz::Tail), and generating events (Franz::Agg)
    #
    # @param [Hash] opts options for the aggregator
    # @option opts [Hash] :input ({}) "input" configuration
    # @option opts [Queue] :output ([]) "output" queue
    # @option opts [Path] :checkpoint ({}) path to checkpoint file
    # @option opts [Integer] :checkpoint_interval ({}) seconds between checkpoints
    # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
    def initialize opts={}
      opts = {
        checkpoint: 'franz.*.checkpoint',
        checkpoint_interval: 30,
        logger: Logger.new(STDOUT),
        output: [],
        input: {
          ignore_before: 0,
          discover_bound: 10_000,
          watch_bound: 1_000,
          tail_bound: 1_000,
          discover_interval: nil,
          watch_interval: nil,
          eviction_interval: nil,
          flush_interval: nil,
          buffer_limit: nil,
          line_limit: nil,
          configs: []
        }
      }.deep_merge!(opts)

      @logger = opts[:logger]

      @checkpoint_interval = opts[:checkpoint_interval]
      @checkpoint_path     = opts[:checkpoint].sub('*', '%d')
      @checkpoint_glob     = opts[:checkpoint]

      # The checkpoint contains a Marshalled Hash with a compact representation of
      # stateful inputs to various Franz streaming classes (e.g. the "known" option
      # to Franz::Discover). This state file is generated automatically every time
      # the input exits (see below) and also at regular intervals.
      checkpoints = Dir[@checkpoint_glob].sort_by { |path| File.mtime path }
      checkpoints = checkpoints.reject { |path| File.zero? path }
      last_checkpoint_path = checkpoints.pop
      state = nil
      unless last_checkpoint_path.nil?
        last_checkpoint = File.read(last_checkpoint_path)
        state = Marshal.load last_checkpoint
        log.info \
          event: 'input checkpoint loaded',
          checkpoint: last_checkpoint_path
      end

      full_state = state.nil? ? nil : state.dup

      state = state || {}
      known = state.keys
      stats, cursors, seqs = {}, {}, {}
      known.each do |path|
        cursor        = state[path].delete :cursor
        seq           = state[path].delete :seq
        cursors[path] = cursor unless cursor.nil?
        seqs[path]    = seq    unless seq.nil?
        stats[path]   = state[path]
      end

      discoveries  = SizedQueue.new opts[:input][:discover_bound]
      deletions    = SizedQueue.new opts[:input][:discover_bound]
      watch_events = SizedQueue.new opts[:input][:watch_bound]
      tail_events  = SizedQueue.new opts[:input][:tail_bound]

      @disover = Franz::Discover.new \
        discoveries: discoveries,
        deletions: deletions,
        configs: opts[:input][:configs],
        discover_interval: opts[:input][:discover_interval],
        ignore_before: opts[:input][:ignore_before],
        logger: opts[:logger],
        known: known,
        full_state: full_state

      @watch = Franz::Watch.new \
        discoveries: discoveries,
        deletions: deletions,
        watch_events: watch_events,
        watch_interval: opts[:input][:watch_interval],
        logger: opts[:logger],
        stats: stats,
        full_state: full_state

      @tail = Franz::Tail.new \
        watch_events: watch_events,
        tail_events: tail_events,
        block_size: opts[:input][:block_size],
        line_limit: opts[:input][:line_limit],
        logger: opts[:logger],
        cursors: cursors,
        full_state: full_state

      @agg = Franz::Agg.new \
        configs: opts[:input][:configs],
        tail_events: tail_events,
        agg_events: opts[:output],
        flush_interval: opts[:input][:flush_interval],
        buffer_limit: opts[:input][:buffer_limit],
        logger: opts[:logger],
        seqs: seqs,
        full_state: full_state

      @stop = false
      @t = Thread.new do
        until @stop
          checkpoint
          sleep @checkpoint_interval
        end
      end

      log.info event: 'input started'
    end

    # Stop everything. Has the effect of draining all the Queues and waiting on
    # auxilliarly threads (e.g. eviction) to complete full intervals, so it may
    # ordinarily take tens of seconds, depending on your configuration.
    #
    # @return [Hash] compact internal state
    def stop
      return state if @stop
      @stop = true
      @t.join
      @watch.stop
      @tail.stop
      @agg.stop
      log.info event: 'input stopped'
      return state
    end

    # Return a compact representation of internal state
    def state
      stats   = @watch.state
      cursors = @tail.state
      seqs    = @agg.state
      stats.keys.each do |path|
        stats[path] ||= {}
        stats[path][:cursor] = cursors.fetch(path, nil)
        stats[path][:seq] = seqs.fetch(path, nil)
      end
      return stats
    end

    # Write a checkpoint file given the current state
    def checkpoint
      old_checkpoints = Dir[@checkpoint_glob].sort_by { |p| File.mtime p }
      path = @checkpoint_path % Time.now
      File.open(path, 'w') { |f| f.write Marshal.dump(state) }
      old_checkpoints.pop # Keep last two checkpoints
      old_checkpoints.map { |c| FileUtils.rm c }
      log.info \
        event: 'input checkpoint saved',
        checkpoint: path
    end

  private
    def log ; @logger end
  end
end