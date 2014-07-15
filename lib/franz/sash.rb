require 'thread'

module Franz

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
  # Think of it like a Hash where the keys map to "value buffers"
  class Sash

    # Create a new, empty Sash.
    def initialize
      @mutex = Mutex.new
      @mtime = Hash.new { |default, key| default[key] = nil }
      @hash  = Hash.new { |default, key| default[key] = []  }
    end

    # Grab a list of known keys.
    #
    # @return [Array]
    def keys ; @hash.keys end

    # Insert a value into a key's value buffer.
    #
    # @param key [Object]
    # @param value [Object]
    #
    # @return [Object] the value
    def insert key, value
      @mutex.synchronize do
        @hash[key] << value
        @mtime[key] = Time.now
      end
      return value
    end

    # Return a key's value buffer.
    #
    # @return [Array]
    def get key ; @hash[key] end

    # Remove and return a key's value buffer.
    #
    # @return [Array]
    def remove key ; @hash.delete(key) end

    # Return the last time the key's value buffer was modified.
    #
    # @return [Time]
    def mtime key ; @mtime[key] end

    # Flush and return a key's value buffer.
    #
    # @return [Array]
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
end