require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'pathname'
require 'minitest/autorun'

require 'slog'
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
    start_agg multiline: /^multiline/
    sleep 3
    seqs = stop_agg
    path = realpath tmp.path
    assert seqs.include?(path)
    assert_equal sample.strip, @agg_events.shift[:message]
    assert seqs[path] == 1 # should be one line
  end

  def test_handles_singular_drop
    sample = "drop this\nbut not this\n"
    tmp    = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_agg drop: /^drop/
    sleep 3
    seqs = stop_agg
    path = realpath tmp.path
    assert seqs.include?(path)
    assert_equal sample.lines.last.strip, @agg_events.shift[:message]
    assert seqs[path] == 1 # should be one line
  end

  def test_handles_plural_drop
    sample = "drop this\nbut not this\nignore this too\nreally\n"
    tmp    = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_agg drop: [ /^drop/, /^ignore/ ]
    sleep 5
    seqs = stop_agg
    path = realpath tmp.path
    assert seqs.include?(path)
    assert_equal sample.lines[1].strip, @agg_events.shift[:message]
    assert_equal sample.lines[3].strip, @agg_events.shift[:message]
    assert seqs[path] == 2 # should be two lines
  end

  def test_handles_singular_keep
    sample = "keep this\nbut not this\n"
    tmp    = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_agg keep: /^keep/
    sleep 3
    seqs = stop_agg
    path = realpath tmp.path
    assert seqs.include?(path)
    assert_equal sample.lines.first.strip, @agg_events.shift[:message]
    assert seqs[path] == 1 # should be one line
  end

  def test_handles_plural_keep
    sample = "keep this\nbut not this\noh this too\nreally\n"
    tmp    = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_agg keep: [ /^keep/, /^oh/ ]
    sleep 5
    seqs = stop_agg
    path = realpath tmp.path
    assert seqs.include?(path)
    assert_equal sample.lines[0].strip, @agg_events.shift[:message]
    assert_equal sample.lines[2].strip, @agg_events.shift[:message]
    assert seqs[path] == 2 # should be two lines
  end

private
  def tempfile prefix=nil
    Tempfile.new prefix, @tmpdir
  end

  def realpath path
    Pathname.new(path).realpath.to_s
  end

  def start_agg config, opts={}
    @configs = [{
      type: :test,
      includes: [ "#{@tmpdir}/*.log", "#{realpath @tmpdir}/*.log" ],
      excludes: [ "#{@tmpdir}/exclude*" ]
    }.merge(config)]

    @ic = Franz::InputConfig.new @configs

    @discover = Franz::Discover.new({
      input_config: @ic,
      discover_interval: 1,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger
    }.deep_merge!(opts))

    @watch = Franz::Watch.new({
      input_config: @ic,
      watch_interval: 1,
      watch_events: @watch_events,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger
    }.deep_merge!(opts))

    @tail = Franz::Tail.new({
      input_config: @ic,
      eviction_interval: 1,
      watch_events: @watch_events,
      tail_events: @tail_events,
      logger: @logger
    }.deep_merge!(opts))

    @agg = Franz::Agg.new({
      input_config: @ic,
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