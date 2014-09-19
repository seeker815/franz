require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'minitest/autorun'

require 'deep_merge'

require_relative '../lib/franz'

Thread.abort_on_exception = true

class TestFranzDiscover < MiniTest::Test
  def setup
    @tmpdir       = Dir.mktmpdir
    @discoveries  = Queue.new
    @deletions    = Queue.new
    @logger       = Logger.new STDERR
    @logger.level = Logger::WARN
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_discovers_existing_file
    tmp = tempfile %w[ test1 .log ]
    start_discovery known: []
    sleep 2 # Time to discover
    known = stop_discovery
    assert known.include?(tmp.path)
  end

  def test_discovers_new_file
    start_discovery known: []
    tmp = tempfile %w[ test2 .log ]
    sleep 3 # Time to discover
    known = stop_discovery
    assert known.include?(tmp.path)
  end

  def test_deletes_deleted_file
    tmp = tempfile %w[ test3 .log ]
    start_discovery known: []
    # at this point, we know Discover has already picked up tmp
    delete tmp.path
    sleep 2
    known = stop_discovery
    assert !known.include?(tmp.path)
  end

  def test_deletes_unknown_file
    tmp = tempfile %w[ test4 .log ]
    delete tmp.path
    # tmp never exists as far as Discover is aware
    start_discovery known: []
    sleep 2
    known = stop_discovery
    assert !known.include?(tmp.path)
  end

private
  def tempfile prefix=nil
    Tempfile.new prefix, @tmpdir
  end

  def start_discovery opts={}
    @discover = Franz::Discover.new({
      discover_interval: 1,
      discoveries: @discoveries,
      deletions: @deletions,
      logger: @logger,
      configs: [{
        includes: [ "#{@tmpdir}/*.log" ],
        excludes: [ "#{@tmpdir}/exclude*" ]
      }]
    }.deep_merge!(opts))
  end

  def stop_discovery
    @discover.stop
  end

  def delete path
    FileUtils.rm_rf path
    @deletions.push path
  end
end