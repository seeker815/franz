require 'thread'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'minitest/autorun'

require 'deep_merge'

require_relative '../lib/franz'


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
    discover_with_opts known: []
    sleep 0.001 # Time to discover
    assert stop.include?(tmp.path)
  end

  def test_discovers_new_file
    discover_with_opts known: []
    tmp = tempfile %w[ test .log ]
    sleep 1 # Time to discover
    assert stop.include?(tmp.path)
  end

  def test_deletes_deleted_file
    tmp = tempfile %w[ test .log ]
    discover_with_opts known: []
    # at this point, we know Discover has already picked up tmp
    delete tmp.path
    sleep 1
    assert !stop.include?(tmp.path)
  end

  def test_deletes_unknown_file
    tmp = tempfile %w[ test .log ]
    delete tmp.path
    # tmp never exists as far as Discover is aware
    discover_with_opts known: []
    sleep 0.001
    assert !stop.include?(tmp.path)
  end

private
  def tempfile prefix=nil
    Tempfile.new(prefix, @tmpdir)
  end

  def discover_with_opts opts={}
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

  def stop
    @discover.stop
  end

  def delete path
    FileUtils.rm_rf path
    @deletions.push path
  end
end