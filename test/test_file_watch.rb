require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'test/unit'

require 'franz/watch'

class TestWatch < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @watch  = Franz::Watch.new \
      includes: File.join(@tmpdir, 'test_*')
    @events = Queue.new
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_file_created
    tmp = tempfile 'test_file_created'

    start
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0)
    ]
  end

  def test_file_created_after_start
    start
    tmp = tempfile 'test_file_created'
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0)
    ]
  end

  def test_file_deleted
    tmp  = tempfile 'test_file_deleted'
    path = tmp.path
    tmp.close

    start
    sleep 1
    tmp.unlink
    sleep 2
    stop

    assert_events [
      event_spec(:created, path, 0, 0),
      event_spec(:deleted, path, 0, 0)
    ]
  end

  def test_reads_existing_file
    tmp = tempfile 'test_reads_existing_file'
    tmp.puts 'Hello, world!'
    tmp.close

    start
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0),
      event_spec(:appended, tmp.path, 0, 14)
    ]
  end

  def test_reads_new_file
    start
    tmp = tempfile 'test_reads_new_file'
    tmp.puts 'Hello, world!'
    tmp.close
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0),
      event_spec(:appended, tmp.path, 0, 14)
    ]
  end

  def test_append_file
    tmp = tempfile 'test_append_file'
    tmp.puts 'Hello, world!'
    tmp.flush

    start
    sleep 3
    tmp.puts 'Hello, world!'
    tmp.close
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0),
      event_spec(:appended, tmp.path, 0, 14),
      event_spec(:appended, tmp.path, 14, 28)
    ]
  end

  def test_rotate_file
    tmp = tempfile 'test_append_file'
    tmp.puts 'Hello, world!'
    tmp.flush

    start
    sleep 3
    tmp.truncate(0)
    tmp.close
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0),
      event_spec(:appended, tmp.path, 0, 14),
      event_spec(:truncated, tmp.path, 14, 0)
    ]
  end

  def test_replace_file
    tmp = tempfile 'test_append_file'
    tmp.puts 'Hello, world!'
    tmp.flush

    replacement = tempfile 'not_watched'
    replacement.puts 'Hello, world!'
    replacement.close

    start
    sleep 3
    FileUtils.ln_sf replacement, tmp
    sleep 2
    stop

    assert_events [
      event_spec(:created, tmp.path, 0, 0),
      event_spec(:appended, tmp.path, 0, 14),
      event_spec(:replaced, tmp.path, 14, 14)
    ]
  end


private
  def start queue=@events
    @watch.start queue
  end

  def stop
    @watch.stop
  end

  def tempfile prefix=nil
    Tempfile.new(prefix, @tmpdir)
  end

  def event_spec type, path, old_size, new_size
    { type: type, path: path, old_size: old_size, new_size: new_size }
  end

  def assert_event spec, event
    assert event.event    == spec[:type]
    assert event.path     == spec[:path]
    assert event.old_size == spec[:old_size]
    assert event.new_size == spec[:new_size]
  end

  def assert_events specs, queue=@events
    specs.each do |spec|
      assert_event spec, queue.shift
    end
    assert queue.empty?
  end
end