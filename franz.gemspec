# -*- encoding: utf-8 -*-
$:.push File.expand_path(File.join('..', 'lib'), __FILE__)
require 'franz/metadata'

Gem::Specification.new do |s|
  s.name        = 'franz'
  s.version     = Franz::VERSION
  s.platform    = Gem::Platform::RUBY
  s.license     = Franz::LICENSE
  s.homepage    = Franz::HOMEPAGE
  s.author      = Franz::AUTHOR
  s.email       = Franz::EMAIL
  s.summary     = Franz::SUMMARY
  s.description = Franz::SUMMARY + '.'

  s.add_runtime_dependency 'slog', '~> 1.1.0'
  s.add_runtime_dependency 'bunny', '~> 1.6.0'
  s.add_runtime_dependency 'trollop', '~> 2.1.0'
  s.add_runtime_dependency 'colorize', '~> 0.7.0'
  s.add_runtime_dependency 'deep_merge', '~> 1.0.0'
  s.add_runtime_dependency 'poseidon', '~> 0.0.5'

  # Bundled libs
  s.add_runtime_dependency 'snappy', '= %s' % Franz::SNAPPY_VERSION
  s.add_runtime_dependency 'eventmachine', '= %s' % Franz::EM_VERSION

  s.files         = Dir['{bin,lib}/**/*'] + %w[ LICENSE Readme.md VERSION ]
  s.test_files    = Dir['test/**/*']
  s.executables   = %w[ franz ]
  s.require_paths = %w[ lib ]
end