require_relative './object_builder'
require_relative './discover'
require_relative './watch'
require_relative './tail'
require_relative './multiline'

Input = Object.new

Object(Input) { |o|
  o.new = ->(configs) {
    @configs = configs

    discoveries  = Queue.new
    deletions    = Queue.new
    watch_events = Queue.new
    tail_events  = Queue.new
    input_events = Queue.new

    Discover.new \
      discoveries: discoveries,
      deletions: deletions,
      configs: configs

    Watch.new \
      discoveries: discoveries,
      deletions: deletions,
      watch_events: watch_events

    Tail.new \
      watch_events: watch_events,
      tail_events: tail_events

    Multiline.new \
      configs: configs,
      tail_events: tail_events,
      multiline_events: input_events

    return input_events
  }
}