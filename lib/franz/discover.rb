class Franz::Discover

  # Create a new Discover object
  #
  # @param opts [Hash, nil] an options hash or nil for defaults
  def initialize opts={}
    @configs     = opts[:configs]     || []
    @discoveries = opts[:discoveries] || []
    @deletions   = opts[:deletions]   || []
    @interval    = opts[:interval]    || 1

    @configs = configs.map do |config|
      config[:includes] ||= []
      config[:excludes] ||= []
      config
    end

    @known = []

    Thread.new do
      loop do
        known.delete deletions.pop until deletions.empty?
        discover.each do |discovery|
          discoveries.push discovery
          known.push discovery
        end
        sleep interval
      end
    end
  end

private
  attr_reader :configs, :discoveries, :deletions, :interval, :known

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