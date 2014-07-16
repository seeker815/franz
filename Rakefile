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
  push: false,
  sign: {}
}) do |tasks|
  tasks.console.command = 'pry'
end
Gem::Tasks::Sign::Checksum.new sha2: true


require 'rake/version_task'
Rake::VersionTask.new


desc "Upload build artifacts to WOPR"
task :upload => :build do
  pkg_name = 'franz-%s.gem' % File.read('VERSION').strip
  pkg_path = File.join 'pkg', pkg_name

  require 'net/ftp'
  ftp = Net::FTP.new
  ftp.connect '10.4.4.15', 8080
  ftp.login
  ftp.passive
  begin
    ftp.put pkg_path
    ftp.sendcmd("SITE CHMOD 0664 #{pkg_name}")
  ensure
    ftp.close
  end
end