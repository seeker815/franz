require 'set'
require 'logger'
require 'shellwords'

require_relative 'stats'


# Discover performs half of file existence detection by expanding globs and
# keeping track of files known to Franz. Discover requires a deletions Queue to
# maintain this state, so it's fairly useless without a Watch.
class Franz::Discover

  # Start a new Discover thread in the background.
  #
  # @param [Hash] opts options for the discovery
  # @option opts [InputConfig] :input_config shared Franz configuration
  # @option opts [Queue] :discoveries ([]) "output" queue of discovered paths
  # @option opts [Queue] :deletions ([]) "input" queue of deleted paths
  # @option opts [Integer] :discover_interval (5) seconds between discover rounds
  # @option opts [Array<Path>] :known ([]) internal "known" state
  # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
  def initialize opts={}
    @ic = opts[:input_config] || raise('No input_config specified')

    @discoveries = opts[:discoveries] || []
    @deletions   = opts[:deletions]   || []

    @discover_interval = opts[:discover_interval] || 30
    @known             = opts[:known]             || []
    @logger            = opts[:logger]            || Logger.new(STDOUT)

    @known = Set.new(@known)

    @configs = @ic.configs.map do |config|
      config[:includes] ||= []
      config[:excludes] ||= []
      config
    end

    @statz = opts[:statz] || Franz::Stats.new
    @statz.create :num_discovered, 0
    @statz.create :num_deleted, 0

    @stop = false

    @thread = Thread.new do
      until @stop
        until deletions.empty?
          d = deletions.pop
          @known.delete d
          @statz.inc :num_deleted
          log.debug \
            event: 'discover deleted',
            file: d
        end

        discover.each do |discovery|
          discoveries.push discovery
          @known.add discovery
          @statz.inc :num_discovered
          log.debug \
            event: 'discover discovered',
            file: discovery
        end
        sleep discover_interval
      end
    end

    log.debug \
      event: 'discover started',
      discoveries: discoveries,
      deletions: deletions,
      discover_interval: discover_interval
  end

  # Stop the Discover thread. Effectively only once.
  #
  # @return [Array] internal "known" state
  def stop
    return state if @stop
    @stop = true
    @thread.kill
    log.debug event: 'discover stopped'
    return state
  end

  # Return the internal "known" state
  def state
    return @known.to_a
  end

private
  attr_reader :configs, :discoveries, :deletions, :discover_interval, :known

  def log ; @logger end

  def discover
    log.debug event: 'discover'
    discovered = []
    configs.each do |config|
      config[:includes].each do |glob|
        Dir[glob].each do |path|
          next if known.include? path
          next if config[:excludes].any? { |exclude|
            File.fnmatch? exclude, File::basename(path), File::FNM_EXTGLOB
          }
          discovered.push path
        end
      end
    end
    return discovered
  end
end