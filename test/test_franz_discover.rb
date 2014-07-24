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
    tmp = tempfile %w[ test .log ]
    start_discovery known: []
    sleep 0.001 # Time to discover
    known = stop_discovery
    assert known.include?(tmp.path)
  end

  def test_discovers_new_file
    start_discovery known: []
    tmp = tempfile %w[ test .log ]
    sleep 1 # Time to discover
    known = stop_discovery
    assert known.include?(tmp.path)
  end

  def test_deletes_deleted_file
    tmp = tempfile %w[ test .log ]
    start_discovery known: []
    # at this point, we know Discover has already picked up tmp
    delete tmp.path
    sleep 1
    known = stop_discovery
    assert !known.include?(tmp.path)
  end

  def test_deletes_unknown_file
    tmp = tempfile %w[ test .log ]
    delete tmp.path
    # tmp never exists as far as Discover is aware
    start_discovery known: []
    sleep 0.001
    known = stop_discovery
    assert !known.include?(tmp.path)
  end

private
  def tempfile prefix=nil
    Tempfile.new prefix, @tmpdir
  end

  def start_discovery opts={}
    @discover = Franz::Discover.new({
      interval: 1,
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