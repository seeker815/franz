# -*- encoding: utf-8 -*-
$:.push File.expand_path(File.join('..', 'lib'), __FILE__)
require 'franz/metadata'

Gem::Specification.new do |s|
  s.name        = 'franz'
  s.version     = Franz::VERSION
  s.platform    = Gem::Platform::RUBY
  s.author      = Franz::AUTHOR
  s.email       = Franz::EMAIL
  s.homepage    = Franz::HOMEPAGE
  s.summary     = Franz::SUMMARY
  s.description = Franz::SUMMARY + '.'

  s.add_runtime_dependency 'bunny'
  s.add_runtime_dependency 'buftok'
  s.add_runtime_dependency 'trollop'
  s.add_runtime_dependency 'colorize'
  s.add_runtime_dependency 'deep_merge'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File::basename(f) }
  s.require_paths = %w[ lib ]
end
