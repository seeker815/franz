require 'thread'
require 'logger'

require 'consistent_hashing'

module Franz

  # TailPool creates a consistenly-hashed pool of Tails.
  class TailPool
    # Start a new TailPool thread in the background.
    #
    # @param opts [Hash] a complex Hash for configuration
    def initialize opts={}
      @size         = opts[:size]         || 5
      @watch_events = opts[:watch_events] || []
      @tail_events  = opts[:tail_events]  || []
      @size         = opts[:size]         || 5
      @logger       = opts[:logger]       || Logger.new(STDOUT)

      @tails  = []
      @ring   = ConsistentHashing::Ring.new
      @events = Hash.new { |h, k| h[k] = SizedQueue.new 10_000 }

      @size.times do |i|
        log.debug 'starting tail_pool-tail #%d' %  i
        @ring << @events[i]
        @tails << Franz::Tail.new(opts.merge({
          watch_events: @events[i],
          tail_events: @tail_events
        }))
      end

      @stop = false

      @in_thread = Thread.new do
        log.debug 'starting tail_pool-watch'
        until @stop
          e = @watch_events.shift
          q = @ring.node_for e[:path]
          q.push e
        end
      end

      log.debug 'started tail_pool'
    end

    # Stop the TailPool thread. Effectively only once.
    #
    # @return [Hash] internal "cursors" state
    def stop
      return state if @stop
      @stop = true
      @tails.map(&:stop)
      log.debug 'stopped tail_pool'
      return state
    end

    # Return the internal "cursors" state
    def state
      @tails.map(&:state).reduce(&:merge)
    end

  private
    attr_reader :watch_events, :tail_events, :size

    def log ; @logger end
  end
end