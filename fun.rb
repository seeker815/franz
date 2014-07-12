#!/usr/bin/env ruby

require_relative './discover'
require_relative './watch'
require_relative './tail'

discoveries  = Queue.new
deletions    = Queue.new
watch_events = Queue.new
tail_events  = Queue.new

configs = [{
  type: :test,
  includes: %w[ * ],
  excludes: %w[ *.rb ],
  multiline: /.*/
}]

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

loop do
  puts tail_events.shift.inspect
end