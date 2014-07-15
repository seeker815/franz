require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'minitest/autorun'

require 'deep_merge'

require_relative '../lib/franz'


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

  def test_watches_existing_file
    tmp = tempfile %w[ test .log ]
    watch_with_opts stats: {}
    sleep 2
    stats = stop
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == 0
  end

  def test_watches_existing_file_with_content
    content = "Hello, world!\n"
    tmp = tempfile %w[ test .log ]
    tmp.write content
    tmp.flush
    watch_with_opts stats: {}
    sleep 2
    stats = stop
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == content.length
  end

  def test_watches_new_file
    watch_with_opts stats: {}
    tmp = tempfile %w[ test .log ]
    sleep 3
    stats = stop
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == 0
  end

  def test_watches_new_file_with_content
    watch_with_opts stats: {}
    content = "Hello, world!\n"
    tmp = tempfile %w[ test .log ]
    tmp.write content
    tmp.flush
    sleep 3
    stats = stop
    assert stats.include?(tmp.path)
    assert stats[tmp.path][:size] == content.length
  end

private
  def tempfile prefix=nil
    Tempfile.new(prefix, @tmpdir)
  end

  def watch_with_opts opts={}
    @discover = Franz::Discover.new({
      interval: 1,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger,
      configs: [{
        includes: [ "#{@tmpdir}/*.log" ],
        excludes: [ "#{@tmpdir}/exclude*" ]
      }]
    })

    @watch = Franz::Watch.new({
      interval: 1,
      watch_events: @queue,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger,
      stats: Hash.new
    }.deep_merge!(opts))
  end

  def stop
    @watch.stop
  end
end