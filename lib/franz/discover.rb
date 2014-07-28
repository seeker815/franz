require 'logger'


# Discover performs half of file existence detection by expanding globs and
# keeping track of files known to Franz. Discover requires a deletions Queue to
# maintain this state, so it's fairly useless without a Watch.
class Franz::Discover

  # Start a new Discover thread in the background.
  #
  # @param [Hash] opts options for the discovery
  # @option opts [Array<Hash>] :configs ([]) file input configuration
  # @option opts [Queue] :discoveries (Queue.new) "output" queue of discovered paths
  # @option opts [Queue] :deletions (Queue.new) "input" queue of deleted paths
  # @option opts [Integer] :discover_interval (5) seconds between discover rounds
  # @option opts [Array<Path>] :known ([]) internal "known" state
  # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
  def initialize opts={}
    @configs           = opts[:configs]           || []
    @discoveries       = opts[:discoveries]       || []
    @deletions         = opts[:deletions]         || []
    @discover_interval = opts[:discover_interval] || 1
    @ignore_before     = opts[:ignore_before]     || 0
    @known             = opts[:known]             || []
    @logger            = opts[:logger]            || Logger.new(STDOUT)

    @configs = configs.map do |config|
      config[:includes] ||= []
      config[:excludes] ||= []
      config
    end

    @stop = false

    @thread = Thread.new do
      log.debug 'starting dicover-delete'
      until @stop
        until deletions.empty?
          d = deletions.pop
          @known.delete d
          log.trace 'deleted: %s' % d.inspect
        end
        discover.each do |discovery|
          discoveries.push discovery
          @known.push discovery
          log.trace 'discovered: %s' % discovery.inspect
        end
        sleep discover_interval
      end
    end

    log.debug 'started discover'
  end

  # Stop the Discover thread. Effectively only once.
  #
  # @return [Array] internal "known" state
  def stop
    return state if @stop
    @stop = true
    @thread.join
    log.debug 'stopped discover'
    return state
  end

  # Return the internal "known" state
  def state
    return @known.dup
  end

private
  attr_reader :configs, :discoveries, :deletions, :discover_interval, :known

  def log ; @logger end

  def discover
    discovered = []
    configs.each do |config|
      config[:includes].each do |glob|
        Dir[glob].each do |path|
          next if config[:excludes].any? { |exclude| File.fnmatch? exclude, path }
          next if known.include? path
          next unless File.file? path
          next if File.mtime(path).to_i <= @ignore_before
          discovered.push path
        end
      end
    end
    return discovered
  end
end