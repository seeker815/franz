# -*- encoding: utf-8 -*-
$:.push File.expand_path(File.join('..', 'lib'), __FILE__)
require 'franz/metadata'

Gem::Specification.new do |s|
  s.name        = 'franz'
  s.version     = Franz::VERSION
  s.platform    = Gem::Platform::RUBY
  s.author      = Franz::AUTHOR
  s.email       = Franz::EMAIL
  s.summary     = Franz::SUMMARY
  s.description = Franz::SUMMARY + '.'

  s.add_runtime_dependency 'slog', '~> 1'
  s.add_runtime_dependency 'bunny', '~> 1'
  s.add_runtime_dependency 'trollop', '~> 2'
  s.add_runtime_dependency 'colorize', '~> 0'
  s.add_runtime_dependency 'deep_merge', '~> 1'
  s.add_runtime_dependency 'eventmachine', '~> 1'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File::basename(f) }
  s.require_paths = %w[ lib ]
end