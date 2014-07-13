require 'thread'


# Sash - A threadsafe hash/array hybrid with access times
#
#     s = Sash.new           # => #<Sash...>
#     s.keys                 # => []
#     s.insert :key, :value  # => value
#     s.get :key             # => [:value]
#     s.insert :key, :crazy  # => :crazy
#     s.mtime :key           # => 2014-02-18 21:24:30 -0800
#     s.flush :key           # => [:value, :crazy]
#
class Sash
  def initialize
    @mutex = Mutex.new
    @mtime = Hash.new { |default, key| default[key] = nil }
    @hash  = Hash.new { |default, key| default[key] = []  }
  end

  def keys ; @hash.keys end

  def insert key, value
    @mutex.synchronize do
      @hash[key] << value
      @mtime[key] = Time.now
    end
    return value
  end

  def get key ; @hash[key] end

  def remove key ; @hash.delete(key) end

  def mtime key ; @mtime[key] end

  def flush key
    value = nil
    @mutex.synchronize do
      value       = @hash[key]
      @hash[key]  = []
      @mtime[key] = Time.now
    end
    return value
  end
end