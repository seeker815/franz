#!/usr/bin/env ruby

require_relative './discover'
require_relative './watch'

discoveries = Queue.new
deletions = Queue.new
events = Queue.new

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
  events: events

loop do
  event = events.shift
  puts 'EVENT => %s' % event
end