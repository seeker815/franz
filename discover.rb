require_relative './object_builder'

Thread.abort_on_exception = true

Discover = Object.new

Object(Discover) { |o|
  o.new = ->(opts) {
    configs     = opts[:configs]     || []
    discoveries = opts[:discoveries] || []
    deletions   = opts[:deletions]   || []
    rest        = opts[:rest]        || 1
    Thread.new do
      known = []
      loop do
        known.delete deletions.pop until deletions.empty?
        discovered = discover configs, known
        known += discovered
        discoveries.push discovered.pop until discovered.empty?
        sleep rest
      end
    end
  }

private
  o.discover = ->(configs, known) {
    discovered = []
    configs.each do |config|
      includes = config[:includes] || []
      excludes = config[:excludes] || []
      includes.each do |glob|
        Dir[glob].each do |path|
          next if excludes.any? { |exclude| File.fnmatch? exclude, path }
          next if known.include? path
          next unless File.file? path
          discovered.push path
        end
      end
    end
    return discovered
  }
}