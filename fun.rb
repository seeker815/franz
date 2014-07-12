#!/usr/bin/env ruby

class ObjectBuilder
  def initialize(object)
    @object = object
  end

  def respond_to_missing?(missing_method, include_private=false)
    missing_method =~ /=\z/
  end

  def method_missing(missing_method, *args, &block)
    if respond_to_missing?(missing_method)
      method_name = missing_method.to_s.sub(/=\z/, '')
      value       = args.first
      ivar_name   = "@#{method_name}"
      if value.is_a?(Proc)
        define_code_method(method_name, ivar_name, value)
      else
        define_value_method(method_name, ivar_name, value)
      end
    else
      super
    end
  end

  def define_value_method(method_name, ivar_name, value)
    @object.instance_variable_set(ivar_name, value)
    @object.define_singleton_method(method_name) do
      instance_variable_get(ivar_name)
    end
  end

  def define_code_method(method_name, ivar_name, implementation)
    @object.instance_variable_set(ivar_name, implementation)
    @object.define_singleton_method(method_name) do |*args|
      instance_exec(*args, &instance_variable_get(ivar_name))
    end
  end
end

def Object(object=nil, &definition)
  obj = object || Object.new
  obj.singleton_class.instance_exec(ObjectBuilder.new(obj), &definition)
  obj
end








# Discover looks out for files being created
discover = Object.new

Object(discover) { |o|
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
        until discovered.empty?
          discoveries.push discovered.pop
        end
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

discoveries = Queue.new

deletions = Queue.new

configs = [{
  type: :test,
  includes: %w[ * ],
  excludes: %w[ *.rb ],
  multiline: /.*/
}]

discover.new \
  discoveries: discoveries,
  deletions: deletions,
  configs: configs

loop do
  discovery = discoveries.shift
  puts discovery
end