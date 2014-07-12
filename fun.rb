#!/usr/bin/env ruby
configs = [{
  type: :test,
  includes: %w[ test*log ],
}]

# require_relative './input'

# input = Queue.new

# Input.new \
#   queue: input,
#   configs: configs


require_relative './discover'

discoveries = Queue.new
deletions   = Queue.new

Discover.new \
  discoveries: discoveries,
  deletions: deletions,
  configs: configs


require_relative './watch'

watch_events = Queue.new

Watch.new \
  discoveries: discoveries,
  deletions: deletions,
  watch_events: watch_events


i = 0
until i == 1_000_000
  puts watch_events.shift.inspect
  i += 1
end