class Franz::Discover
  def initialize opts={}
    @configs     = opts[:configs]     || []
    @discoveries = opts[:discoveries] || []
    @deletions   = opts[:deletions]   || []
    @interval    = opts[:interval]    || 1
    @known       = opts[:known]       || []

    @configs = configs.map do |config|
      config[:includes] ||= []
      config[:excludes] ||= []
      config
    end

    @stop = false

    @thread = Thread.new do
      until @stop
        @known.delete deletions.pop until deletions.empty?
        discover.each do |discovery|
          discoveries.push discovery
          @known.push discovery
        end
        sleep interval
      end
    end
  end

  def stop
    @stop = true
    @thread.join
    return @known
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