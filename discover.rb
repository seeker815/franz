require_relative './object_builder'

Thread.abort_on_exception = true

Discover = Object.new

Object(Discover) { |o|
  o.new = ->(opts) {
    configs     = opts[:configs]     || []
    discoveries = opts[:discoveries] || []
    deletions   = opts[:deletions]   || []
    rest        = opts[:rest]        || 1

    configs = configs.map do |config|
      config[:includes]  ||= []
      config[:excludes]  ||= []
      config[:multiline] ||= nil
      config
    end

    Thread.new do
      known = []
      loop do
        known.delete deletions.pop until deletions.empty?
        discovered = discover configs, known
        known += discovered.map(&:first)
        discoveries.push discovered.pop until discovered.empty?
        sleep rest
      end
    end
  }

private
  o.type_given = ->(path, configs) {
    configs.each do |config|
      return config[:type] if config[:includes].any? { |glob|
        File.fnmatch?(glob, path) && !config[:excludes].any? { |xglob|
          File.fnmatch?(xglob, path)
        }
      }
    end
    return nil
  }

  o.discover = ->(configs, known) {
    discovered = []
    configs.each do |config|
      includes = config[:includes]
      excludes = config[:excludes]
      includes.each do |glob|
        Dir[glob].each do |path|
          next if excludes.any? { |exclude| File.fnmatch? exclude, path }
          next if known.include? path
          next unless File.file? path
          discovered.push [ path, type_given(path, configs) ]
        end
      end
    end
    return discovered
  }
}