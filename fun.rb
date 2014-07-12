#!/usr/bin/env ruby
require 'json'

require_relative './input'

input = Input.new [{
  type: :one,
  includes: %w[ test.1.log ],
  multiline: /.*/
}, {
  type: :two,
  includes: %w[ test.2.log ]
}, {
  type: :three,
  includes: %w[ test.3*.log ],
  excludes: %w[ test.3.log ],
  multiline: /^\[/
}]

loop do
  puts input.shift.inspect
end