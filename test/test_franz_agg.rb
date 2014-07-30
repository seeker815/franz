require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'pathname'
require 'minitest/autorun'

require 'deep_merge'

require_relative '../lib/franz'

Thread.abort_on_exception = true

class TestFranzAgg < MiniTest::Test
  def setup
    @tmpdir       = Dir.mktmpdir
    @discoveries  = Queue.new
    @deletions    = Queue.new
    @watch_events = Queue.new
    @tail_events  = Queue.new
    @agg_events   = Queue.new
    @logger       = Logger.new STDERR
    @logger.level = Logger::WARN
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_handles_multiline
    sample = "multiline this\nand this should be included\n"
    tmp    = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_agg
    sleep 3
    seqs = stop_agg
    path = realpath tmp.path
    assert seqs.include?(path)
    assert_equal sample.strip, @agg_events.shift[:message]
    assert seqs[path] == 1 # should be one line
  end

private
  def tempfile prefix=nil
    Tempfile.new prefix, @tmpdir
  end

  def realpath path
    Pathname.new(path).realpath.to_s
  end

  def start_agg opts={}
    configs = [{
      type: :test,
      multiline: /^multiline/,
      includes: [ "#{@tmpdir}/*.log", "#{realpath @tmpdir}/*.log" ],
      excludes: [ "#{@tmpdir}/exclude*" ]
    }]

    @discover = Franz::Discover.new({
      discover_interval: 1,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger,
      configs: configs
    }.deep_merge!(opts))

    @watch = Franz::Watch.new({
      watch_interval: 1,
      watch_events: @watch_events,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger
    }.deep_merge!(opts))

    @tail = Franz::Tail.new({
      eviction_interval: 1,
      watch_events: @watch_events,
      tail_events: @tail_events,
      logger: @logger
    }.deep_merge!(opts))

    @agg = Franz::Agg.new({
      configs: configs,
      flush_interval: 2,
      tail_events: @tail_events,
      agg_events: @agg_events,
      logger: @logger
    }.deep_merge!(opts))
  end

  def stop_agg
    @agg.stop
  end
end