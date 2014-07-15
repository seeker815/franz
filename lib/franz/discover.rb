require 'logger'


# Discover performs half of file existence detection by expanding globs and
# keeping track of files known to Franz. Discover requires a deletions Queue to
# maintain this state, so it's fairly useless without a Watch.
class Franz::Discover

  # Start a new Discover thread in the background.
  #
  # @param opts [Hash] a complex Hash for discovery configuration
  def initialize opts={}
    @configs     = opts[:configs]     || []
    @discoveries = opts[:discoveries] || []
    @deletions   = opts[:deletions]   || []
    @interval    = opts[:interval]    || 1
    @known       = opts[:known]       || []
    @logger      = opts[:logger]      || Logger.new(STDOUT)

    @configs = configs.map do |config|
      config[:includes] ||= []
      config[:excludes] ||= []
      config
    end

    @stop = false

    @thread = Thread.new do
      until @stop
        until deletions.empty?
          d = deletions.pop
          @known.delete d
          log.debug 'deleted: %s' % d.inspect
        end
        discover.each do |discovery|
          discoveries.push discovery
          @known.push discovery
          log.debug 'discovered: %s' % discovery.inspect
        end
        sleep interval
      end
    end
  end

  # Stop the Discover thread. Effectively only once.
  #
  # @return [Array] internal "known" state
  def stop
    return @known if @stop
    @stop = true
    @thread.join
    return @known
  end

private
  attr_reader :configs, :discoveries, :deletions, :interval, :known

  def log ; @logger end

  def discover
    discovered = []
    configs.each do |config|
      config[:includes].each do |glob|
        Dir[glob].each do |path|
          next if config[:excludes].any? { |exclude| File.fnmatch? exclude, path }
          next if known.include? path
          next unless File.file? path
          discovered.push path
        end
      end
    end
    return discovered
  end
end