require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'pathname'
require 'minitest/autorun'

require 'deep_merge'

require_relative '../lib/franz'

Thread.abort_on_exception = true

class TestPerformance < MiniTest::Test
  def setup
    @ulimit = Process.getrlimit(:NOFILE).first

    @discover_interval = 2
    @watch_interval    = 2
    @eviction_interval = 2
    @flush_interval    = 2

    @tmpdir       = File.join(Dir.pwd, 'tmp')
    @discoveries  = Queue.new
    @deletions    = Queue.new
    @watch_events = Queue.new
    @tail_events  = Queue.new
    @agg_events   = Queue.new
    @logger       = Logger.new STDERR
    @logger.level = Logger::WARN

    FileUtils.rm_rf @tmpdir
    FileUtils.mkdir_p @tmpdir
  end

  def teardown
    # nop
  end

  def test_handles_too_many_files_for_ulimit
    sample = "Why, hello there, World! How lovely to see you this morning."
    num_files = @ulimit * 2
    num_lines_per_file = 100

    paths = []
    num_files.times do |i|
      path = File.join(@tmpdir, "test.#{i}.log")
      File.open(path, 'w') do |f|
        num_lines_per_file.times do
          f.puts sample
        end
      end
      paths << path
    end

    num_events = num_files * num_lines_per_file

    start_agg
    started = Time.now
    until @agg_events.size == num_events
      sleep 1
    end
    seqs = stop_agg
    elapsed = Time.now - started

    @logger.fatal('%ds elapsed' % elapsed)
    @logger.fatal('%d events' % num_events)
    @logger.fatal('%f events/s' % ( (1.0 * num_events) / (1.0 * elapsed) ))
    assert_equal(paths.size, seqs.keys.size)
    assert_equal(paths.size * num_lines_per_file, @agg_events.size)
  end



private
  def tempfile prefix=nil
    Tempfile.new prefix, @tmpdir
  end

  def realpath path
    Pathname.new(path).realpath.to_s.gsub(/^\/private/, '')
  end

  def start_agg opts={}
    @configs = [{
      type: :test,
      includes: [ "#{@tmpdir}/*.log" ],
      excludes: [ "#{@tmpdir}/exclude*" ]
    }]

    @ic = Franz::InputConfig.new @configs

    @discover = Franz::Discover.new({
      input_config: @ic,
      discover_interval: @discover_interval,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger
    }.deep_merge!(opts))

    @watch = Franz::Watch.new({
      input_config: @ic,
      watch_interval: @watch_interval,
      watch_events: @watch_events,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger
    }.deep_merge!(opts))

    @tail = Franz::Tail.new({
      input_config: @ic,
      eviction_interval: @eviction_interval,
      watch_events: @watch_events,
      tail_events: @tail_events,
      logger: @logger
    }.deep_merge!(opts))

    @agg = Franz::Agg.new({
      input_config: @ic,
      flush_interval: @flush_interval,
      tail_events: @tail_events,
      agg_events: @agg_events,
      logger: @logger
    }.deep_merge!(opts))
  end

  def stop_agg
    @agg.stop
  end
end