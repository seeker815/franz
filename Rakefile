require 'rubygems'
require 'bundler'
require 'rake'

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test

require 'yard'
YARD::Rake::YardocTask.new


require 'rubygems/tasks'
Gem::Tasks.new({
  :push => false,
  :build => { tar: true },
  :sign => { checksum: true }
}) do |tasks|
  tasks.console.command = 'pry'
end