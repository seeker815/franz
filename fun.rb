#!/usr/bin/env ruby
require_relative './input'

input = Queue.new

Input.new \
  queue: input,
  configs: [{
    type: :one,
    includes: %w[ test.1.log ],
    multiline: /.*/
  }]

Input.new \
  queue: input,
  configs: [{
    type: :two,
    includes: %w[ test.2.log ]
  }]

Input.new \
  queue: input,
  configs: [{
    type: :three,
    includes: %w[ test.3*.log ],
    excludes: %w[ test.3.log ],
    multiline: /^\[/
  }]

loop do
  puts input.shift.inspect
end