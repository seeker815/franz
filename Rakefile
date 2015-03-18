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
SNAPPY_VERSION = '0.0.11'
EM_VERSION = '1.0.5'

desc 'Package Franz into binaries'
task package: %w[ package:linux package:osx ]

namespace :package do
  desc 'Package Franz for Linux (x86_64)'
  task linux: [
    :bundle_install,
    "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz",
    "pkg/snappy-#{SNAPPY_VERSION}-linux-x86_64.tar.gz",
    "pkg/eventmachine-#{EM_VERSION}-linux-x86_64.tar.gz"
  ] do
    create_package 'linux-x86_64'
  end

  desc 'Package Franz for OS X'
  task osx: [
    :bundle_install,
    "pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx.tar.gz",
    "pkg/snappy-#{SNAPPY_VERSION}-osx.tar.gz",
    "pkg/eventmachine-#{EM_VERSION}-osx.tar.gz"
  ] do
    create_package 'osx'
  end

  desc 'Install gems to local directory'
  task :bundle_install do
    if RUBY_VERSION !~ /^2\.1\./
      abort "You can only 'bundle install' using Ruby 2.1, because that's what Traveling Ruby uses."
    end
    sh "rm -rf pkg/tmp pkg/vendor"
    sh "mkdir pkg/tmp"
    sh "cp -R franz.gemspec Readme.md LICENSE VERSION Gemfile Gemfile.lock bin lib pkg/tmp"
    Bundler.with_clean_env do
      sh "cd pkg/tmp && env BUNDLE_IGNORE_CONFIG=1 bundle install --path vendor --without development"
      sh "mv pkg/tmp/vendor pkg"
    end
    sh "rm -rf pkg/tmp"
    sh "rm -f pkg/vendor/*/*/cache/*"
    sh "rm -rf pkg/vendor/ruby/*/extensions"
    sh "find pkg/vendor/ruby/*/gems -name '*.so' | xargs rm -f"
    sh "find pkg/vendor/ruby/*/gems -name '*.bundle' | xargs rm -f"
    sh "find pkg/vendor/ruby/*/gems -name '*.o' | xargs rm -f"
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

file "pkg/snappy-#{SNAPPY_VERSION}-linux-x86_64.tar.gz" do
  download_extension 'snappy', 'linux-x86_64'
end

file "pkg/eventmachine-#{EM_VERSION}-linux-x86_64.tar.gz" do
  download_extension 'eventmachine', 'linux-x86_64'
end

file "pkg/snappy-#{SNAPPY_VERSION}-osx.tar.gz" do
  download_extension 'snappy', 'osx'
end

file "pkg/eventmachine-#{EM_VERSION}-osx.tar.gz" do
  download_extension 'eventmachine', 'osx'
end

def create_package target
  package_dir = "franz-#{Franz::VERSION}-#{target}"
  sh "rm -rf #{package_dir}"
  sh "mkdir -p #{package_dir}/franz/app"
  sh "cp -R bin #{package_dir}/franz/app"
  sh "cp -R lib #{package_dir}/franz/app"
  sh "mkdir #{package_dir}/franz/ruby"
  sh "tar -xzf pkg/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz -C #{package_dir}/franz/ruby"
  sh "cp pkg/wrapper.sh #{package_dir}/franz.sh"
  sh "cp -pR pkg/vendor #{package_dir}/franz/vendor"
  sh "cp -R franz.gemspec Readme.md LICENSE VERSION Gemfile Gemfile.lock bin lib #{package_dir}/franz/vendor"
  sh "mkdir #{package_dir}/franz/vendor/.bundle"
  sh "cp pkg/bundler-config #{package_dir}/franz/vendor/.bundle/config"
  sh "tar -xzf pkg/snappy-#{SNAPPY_VERSION}-#{target}.tar.gz -C #{package_dir}/franz"
  sh "tar -xzf pkg/eventmachine-#{EM_VERSION}-#{target}.tar.gz -C #{package_dir}/franz"
  sh %Q~
    which fpm && fpm --verbose \
      -s dir -t deb -C #{package_dir} \
      -n franz -v #{Franz::VERSION} \
      --license ISC \
      --description "Franz" \
      --maintainer "Sean Clemmer <sclemmer@bluejeans.com>" \
      --vendor "Blue Jeans Network" \
      franz.sh=/usr/local/bin/franz \
      franz=/usr/local/lib
  ~
  if !ENV['DIR_ONLY']
    sh "tar -czf #{package_dir}.tar.gz #{package_dir}"
    sh "rm -rf #{package_dir}"
  end
end

def download_extension name, platform
  version = case name
  when 'snappy' ; SNAPPY_VERSION
  when 'eventmachine' ; EM_VERSION
  end
  url = 'https://dl.dropboxusercontent.com/u/431514/%s-%s-%s.tar.gz' % [
    name, version, platform
  ]
  sh 'cd pkg && curl -L -O --fail ' + url
end

def download_runtime target
  sh 'cd pkg && curl -L -O --fail ' +
    "http://d6r77u77i8pq3.cloudfront.net/releases/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz"
end
