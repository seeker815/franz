require 'rubygems'
require 'bundler'
require 'rake'


require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/test*.rb']
  test.verbose = true
end

task :default => :test


require 'yard'
YARD::Rake::YardocTask.new do |t|
  t.files = %w[ --readme Readme.md lib/**/*.rb - VERSION ]
end


require 'rubygems/tasks'
Gem::Tasks.new({
  sign: {}
}) do |tasks|
  tasks.console.command = 'pry'
end
Gem::Tasks::Sign::Checksum.new sha2: true


require 'rake/version_task'
Rake::VersionTask.new




require 'franz'

TRAVELING_RUBY_VERSION = '20150210-2.1.5'

desc 'Package Franz into binaries'
task package: %w[
  package:linux:x86
  package:linux:x86_64
  package:osx
]

namespace :package do
  namespace :linux do
    desc 'Package Franz for Linux x86'
    task x86: [
      :bundle_install,
      "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86.tar.gz"
    ] do
      create_package 'linux-x86'
    end

    desc 'Package Franz for Linux x86_64'
    task x86_64: [
      :bundle_install,
      "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz"
    ] do
      create_package 'linux-x86_64'
    end
  end

  desc 'Package Franz for OS X'
  task osx: [
    :bundle_install,
    "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx.tar.gz"
  ] do
    create_package 'osx'
  end

  desc 'Install gems to local directory'
  task :bundle_install do
    if RUBY_VERSION !~ /^2\.1\./
      abort "You can only 'bundle install' using Ruby 2.1, because that's what Traveling Ruby uses."
    end
    sh "rm -rf pkg/tmp"
    sh "mkdir pkg/tmp"
    sh "cp -R franz.gemspec Readme.md LICENSE VERSION Gemfile Gemfile.lock {bin,lib} pkg/tmp"
    Bundler.with_clean_env do
      sh "cd pkg/tmp && env BUNDLE_IGNORE_CONFIG=1 bundle install --path ../vendor --without development"
    end
    sh "rm -rf pkg/tmp"
    sh "rm -f pkg/vendor/*/*/cache/*"
  end
end

file "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86.tar.gz" do
  download_runtime 'linux-x86'
end

file "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz" do
  download_runtime 'linux-x86_64'
end

file "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx.tar.gz" do
  download_runtime 'osx'
end

def create_package target
  package_dir = "franz-#{Franz::VERSION}-#{target}"
  sh "rm -rf #{package_dir}"
  sh "mkdir -p #{package_dir}/.app"
  sh "cp -R bin #{package_dir}/.app"
  sh "cp -R lib #{package_dir}/.app"
  sh "mkdir #{package_dir}/.ruby"
  sh "tar -xzf pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz -C #{package_dir}/.ruby"
  sh "cp pkg/wrapper.sh #{package_dir}/franz"
  sh "cp -pR pkg/vendor #{package_dir}/.vendor"
  sh "cp -R franz.gemspec Readme.md LICENSE VERSION Gemfile Gemfile.lock {bin,lib} #{package_dir}/.vendor/"
  sh "mkdir #{package_dir}/.vendor/.bundle"
  sh "cp pkg/bundler-config #{package_dir}/.vendor/.bundle/config"
  if !ENV['DIR_ONLY']
    sh "tar -czf #{package_dir}.tar.gz #{package_dir}"
    sh "rm -rf #{package_dir}"
  end
end

def download_runtime target
  sh "cd pkg && curl -L -O --fail " +
    "http://d6r77u77i8pq3.cloudfront.net/releases/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz"
end