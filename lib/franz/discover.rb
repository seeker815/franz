require 'logger'
require 'shellwords'


# Discover performs half of file existence detection by expanding globs and
# keeping track of files known to Franz. Discover requires a deletions Queue to
# maintain this state, so it's fairly useless without a Watch.
class Franz::Discover

  # Start a new Discover thread in the background.
  #
  # @param [Hash] opts options for the discovery
  # @option opts [Array<Hash>] :configs ([]) file input configuration
  # @option opts [Queue] :discoveries ([]) "output" queue of discovered paths
  # @option opts [Queue] :deletions ([]) "input" queue of deleted paths
  # @option opts [Integer] :discover_interval (5) seconds between discover rounds
  # @option opts [Array<Path>] :known ([]) internal "known" state
  # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
  def initialize opts={}
    @configs     = opts[:configs]     || []
    @discoveries = opts[:discoveries] || []
    @deletions   = opts[:deletions]   || []

    @discover_interval = opts[:discover_interval] || 30
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
      until @stop
        known_size = @known.size
        discoveries_size = discoveries.size
        deletions_size = deletions.size
        cp_started = Time.now

        until deletions.empty?
          d = deletions.pop
          @known.delete d
          log.debug \
            event: 'discover deleted',
            path: d
        end
        cp_handled_deletes = Time.now

        discovered = discover
        cp_discovered = Time.now

        discovered.each do |discovery|
          discoveries.push discovery
          @known.push discovery
          log.debug \
            event: 'discover discovered',
            path: discovery
        end
        cp_handled_discoveries = Time.now

        elapsed_total = cp_handled_discoveries - cp_started
        elapsed_handling_discoveries = cp_handled_discoveries - cp_discovered
        elapsed_in_discovery = cp_discovered - cp_handled_deletes
        elapsed_handling_deletes = cp_handled_deletes - cp_started

        log.debug \
          event: 'discover finished',
          elapsed_total: elapsed_total,
          elapsed_handling_deletes: elapsed_handling_deletes,
          elapsed_in_discovery: elapsed_in_discovery,
          elapsed_handling_discoveries: elapsed_handling_discoveries,
          known_size_before: known_size,
          known_size_after: @known.size,
          discoveries_size_before: discoveries_size,
          discoveries_size_after: discoveries.size,
          deletions_size_before: deletions_size,
          deletions_size_after: deletions.size
        sleep discover_interval
      end
    end

    log.info \
      event: 'discover started',
      configs: configs,
      discoveries: discoveries,
      deletions: deletions,
      discover_interval: discover_interval,
      ignore_before: ignore_before
  end

  # Stop the Discover thread. Effectively only once.
  #
  # @return [Array] internal "known" state
  def stop
    return state if @stop
    @stop = true
    @thread.kill
    log.info event: 'discover stopped'
    return state
  end

  # Return the internal "known" state
  def state
    return @known.dup
  end

private
  attr_reader :configs, :discoveries, :deletions, :discover_interval, :known, :ignore_before

  def log ; @logger end

  def discover
    discovered = []
    configs.each do |config|
      config[:includes].each do |glob|
        expand(glob).each do |path|
          next if known.include? path
          next if config[:excludes].any? { |exclude|
            File.fnmatch? exclude, File::basename(path)
          }
          next unless File.file? path
          next if File.mtime(path).to_i <= @ignore_before
          discovered.push path
        end
      end
    end
    return discovered
  end

  def expand glob
    dir_glob = File.dirname(glob)
    file_glob = File.basename(glob)
    files = []
    Dir.glob(dir_glob).each do |dir|
      next unless File::directory?(dir)
      entries = `find #{Shellwords.escape(dir)} -maxdepth 1 -type f 2>/dev/null`.lines.map do |e|
        File::basename(e.strip)
      end
      entries.each do |fname|
        next if fname == '.' || fname == '..'
        next unless File.fnmatch?(file_glob, fname)
        files << File.join(dir, fname)
      end
    end
    files
  end
end