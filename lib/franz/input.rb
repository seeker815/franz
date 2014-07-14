require 'thread'

require_relative 'discover'
require_relative 'watch'
require_relative 'tail'
require_relative 'multiline'
require_relative 'bounded_queue'


class Franz::Input
  def initialize opts={}
    opts = {
      queue: Queue.new,
      configs: [],
      discover_interval: nil,
      watch_interval: nil
    }.merge(opts)

    discoveries  = Franz::BoundedQueue.new 4096
    deletions    = Franz::BoundedQueue.new 4096
    watch_events = Franz::BoundedQueue.new 4096
    tail_events  = Franz::BoundedQueue.new 4096

    @d = Franz::Discover.new \
      discoveries: discoveries,
      deletions: deletions,
      configs: opts[:configs],
      interval: opts[:discover_interval]

    @w = Franz::Watch.new \
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events,
      interval: opts[:watch_interval]

    @t = Franz::Tail.new \
      watch_events: watch_events,
      tail_events: tail_events

    @m = Franz::Multiline.new \
      configs: opts[:configs],
      tail_events: tail_events,
      multiline_events: opts[:queue]
  end

  def stop
    @d.stop
    @w.stop
    @t.stop
    @m.stop
  end
end