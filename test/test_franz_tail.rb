require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'minitest/autorun'

require 'slog'
require 'deep_merge'

require_relative '../lib/franz'

Thread.abort_on_exception = true

class TestFranzTail < MiniTest::Test
  def setup
    @tmpdir       = Dir.mktmpdir
    @discoveries  = Queue.new
    @deletions    = Queue.new
    @watch_events = Queue.new
    @tail_events  = Queue.new
    @logger       = Logger.new STDERR
    @logger.level = Logger::WARN
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_handles_reading_after_deletion
    sample = "Hello, world!\n"
    start_tail
    tmp = tempfile %w[ test4 .log ]
    path = tmp.path
    tmp.write sample
    tmp.flush
    tmp.close
    sleep 1
    FileUtils.rm_rf path
    sleep 2
    File.open(path, 'w') do |f|
      f.write sample
      f.flush
    end
    sleep 4
    cursors = stop_tail
    assert cursors.include?(tmp.path)
    assert cursors[tmp.path] == sample.length
  end

  def test_handles_existing_file
    sample = "Hello, world!\n"
    tmp = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_tail
    sleep 3
    cursors = stop_tail
    assert cursors.include?(tmp.path)
    assert cursors[tmp.path] == sample.length
  end

  def test_handles_new_file
    sample = "Hello, world!\n"
    start_tail
    sleep 0
    tmp = tempfile %w[ test2 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    sleep 3
    cursors = stop_tail
    assert cursors.include?(tmp.path)
    assert cursors[tmp.path] == sample.length
  end

  def test_handles_reading_after_eviction
    sample = "Hello, world!\n"
    eviction_interval = 2
    start_tail eviction_interval: eviction_interval
    sleep 0
    tmp = tempfile %w[ test3 .log ]
    tmp.write sample
    tmp.flush
    sleep eviction_interval / 2
    tmp.write sample
    tmp.flush
    tmp.close
    sleep eviction_interval * 2
    cursors = stop_tail
    assert cursors.include?(tmp.path)
    assert cursors[tmp.path] == sample.length * 2
  end

  def test_handles_large_read
    sample = 10_000.times.map do
      "Hello, world!"
    end.join("\n")
    tmp = tempfile %w[ test1 .log ]
    tmp.write sample
    tmp.flush
    tmp.close
    start_tail
    sleep 3
    cursors = stop_tail
    assert cursors.include?(tmp.path)
    assert cursors[tmp.path] == sample.length
  end

private
  def tempfile prefix=nil
    Tempfile.new prefix, @tmpdir
  end

  def start_tail opts={}
    @configs = [{
      includes: [ "#{@tmpdir}/*.log" ],
      excludes: [ "#{@tmpdir}/exclude*" ]
    }]

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
  end

  def stop_tail
    @tail.stop
  end
end