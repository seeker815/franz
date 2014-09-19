require 'fileutils'
require 'shellwords'

NFILES = ARGV[0].nil? ? 25_000 : ARGV[0].to_i

Thread.abort_on_exception = true

def expand glob
  dir_glob = File.dirname(glob)
  file_glob = File.basename(glob)
  files = []
  Dir.glob(dir_glob).each do |dir|
    next unless File::directory?(dir)
    entries = `find #{Shellwords.escape(dir)} -maxdepth 1 -type f 2>/dev/null`.lines.map do |e|
      File::basename(e.strip)
    end
    entries.each do |fname|
      next if fname == '.' || fname == '..'
      next unless File.fnmatch?(file_glob, fname)
      files << File.join(dir, fname)
    end
  end
  files
end

tmpdir = File.join(Dir.pwd, 'tmp')
FileUtils.rm_rf tmpdir
FileUtils.mkdir_p tmpdir

$stderr.puts 'Populating %d files' % NFILES
started0 = Time.now
glob = File.join(tmpdir, "test.*.log")
paths = []
NFILES.times do |i|
  path = File.join(tmpdir, "test.#{i}.log")
  FileUtils.touch(path)
  puts i if i % 1000 == 0
  paths << path
end
elapsed0 = Time.now - started0
$stderr.puts '%fs elapsed' % elapsed0

$stderr.puts('Starting Dir.glob test...')
started1 = Time.now
paths1   = Dir.glob(glob)
ended1   = Time.now
elapsed1 = ended1 - started1
$stderr.puts('%fs elapsed1' % elapsed1)

$stderr.puts('Starting Discover.expand test...')
started2 = Time.now
paths2   = expand(glob)
ended2   = Time.now
elapsed2 = ended2 - started2
$stderr.puts('%fs elapsed2' % elapsed2)

paths.sort!
paths1.sort!
paths2.sort!

raise unless paths == paths1
raise unless paths == paths2

FileUtils.rm_rf tmpdir