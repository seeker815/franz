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