require 'thread'

require_relative 'discover'
require_relative 'watch'
require_relative 'tail'
require_relative 'multiline'


class Franz::Input
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

    Franz::Discover.new \
      discoveries: discoveries,
      deletions: deletions,
      configs: opts[:configs],
      interval: opts[:discover_interval]

    Franz::Watch.new \
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events,
      interval: opts[:watch_interval]

    Franz::Tail.new \
      watch_events: watch_events,
      tail_events: tail_events

    Franz::Multiline.new \
      configs: opts[:configs],
      tail_events: tail_events,
      multiline_events: opts[:queue]
  end
end