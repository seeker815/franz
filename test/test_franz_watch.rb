require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'minitest/autorun'

require 'deep_merge'

require_relative '../lib/franz'

Thread.abort_on_exception = true

class TestFranzWatch < MiniTest::Test
  def setup
    @tmpdir       = Dir.mktmpdir
    @discoveries  = Queue.new
    @deletions    = Queue.new
    @queue        = Queue.new
    @logger       = Logger.new STDERR
    @logger.level = Logger::WARN
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_handles_existing_file
    tmp = tempfile %w[ test1 .log ]
    start_watch
    sleep 2
    stats = stop_watch
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == 0
  end

  def test_handles_existing_file_with_content
    content = "Hello, world!\n"
    tmp = tempfile %w[ test2 .log ]
    tmp.write content
    tmp.flush
    start_watch
    sleep 2
    stats = stop_watch
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == content.length
  end

  def test_handles_new_file
    start_watch
    tmp = tempfile %w[ test3 .log ]
    sleep 3
    stats = stop_watch
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == 0
  end

  def test_handles_new_file_with_content
    start_watch
    content = "Hello, world!\n"
    tmp = tempfile %w[ test4 .log ]
    tmp.write content
    tmp.flush
    sleep 3
    stats = stop_watch
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == content.length
  end

  def test_handles_file_truncated
    long_content = "Hello, world!\n"
    short_content = "Bye!\n"

    tmp = tempfile %w[ test5 .log ]
    tmp.write long_content
    tmp.flush

    start_watch
    sleep 2
    tmp.rewind
    tmp.truncate 0
    tmp.write short_content
    tmp.flush
    sleep 3

    stats = stop_watch
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == short_content.length
  end

  def test_handles_file_replaced
    content1 = "Hello, world!\n"
    content2 = "Bye!\n"

    tmp1 = tempfile %w[ test6 .log ]
    tmp1.write content1
    tmp1.flush
    tmp1.close

    tmp2 = tempfile %w[ exclude6 .log ]
    tmp2.write content2
    tmp2.flush
    tmp2.close

    start_watch
    sleep 2
    FileUtils.ln_sf tmp2.path, tmp1.path
    sleep 3

    stats = stop_watch
    assert stats.include?(tmp1.path)
    assert stats[tmp1.path][:size] == content2.length
  end

private
  def tempfile prefix=nil
    Tempfile.new(prefix, @tmpdir)
  end

  def start_watch opts={}
    @discover = Franz::Discover.new({
      discover_interval: 1,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger,
      configs: [{
        includes: [ "#{@tmpdir}/*.log" ],
        excludes: [ "#{@tmpdir}/exclude*" ]
      }]
    })

    @watch = Franz::Watch.new({
      watch_interval: 1,
      watch_events: @queue,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger,
      stats: Hash.new
    }.deep_merge!(opts))
  end

  def stop_watch
    @watch.stop
  end
end