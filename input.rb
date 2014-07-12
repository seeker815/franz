require 'thread'

require_relative './discover'
require_relative './watch'
require_relative './tail'
require_relative './multiline'

class Input
  def initialize opts={}
    opts = {
      queue: Queue.new,
      configs: [],
      discover_interval: nil,
      watch_interval: nil
    }.merge(opts)

    discoveries  = Queue.new
    deletions    = Queue.new
    watch_events = Queue.new
    tail_events  = Queue.new

    Discover.new \
      discoveries: discoveries,
      deletions: deletions,
      configs: opts[:configs],
      interval: opts[:discover_interval]

    Watch.new \
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events,
      interval: opts[:watch_interval]

    Tail.new \
      watch_events: watch_events,
      tail_events: tail_events

    Multiline.new \
      configs: opts[:configs],
      tail_events: tail_events,
      multiline_events: opts[:queue]
  end
end