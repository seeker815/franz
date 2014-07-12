require_relative './object_builder'
require_relative './discover'
require_relative './watch'
require_relative './tail'
require_relative './multiline'

Input = Object.new

Object(Input) { |o|
  o.new = ->(opts={}) {
    opts = {
      configs: [],
      discover_interval: nil,
      watch_interval: nil
    }.merge(opts)

    discoveries  = Queue.new
    deletions    = Queue.new
    watch_events = Queue.new
    tail_events  = Queue.new
    input_events = Queue.new

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
      multiline_events: input_events

    return input_events
  }
}