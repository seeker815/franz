# An only very slighly modified version of Tapas::Queue, a bounded Queue
# developed by Avdi Grimm for RubyTapas. You can check out the source here:
#
#                 https://github.com/avdi/tapas-queue
#
# Copyright (c) 2013 Avdi Grimm
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
require 'thread'

module Franz

  # Bind a condition variable to a mutex.
  class Condition

    # Create a new Condition.
    #
    # @param lock [Mutex] mutex to use
    def initialize lock
      @lock = lock
      @cond = ConditionVariable.new
    end

    # Wait on the condition variable.
    #
    # @param timeout [Integer] timeout in seconds on wait
    def wait timeout=nil
      @cond.wait @lock, timeout
    end

    # Signal the condition variaable.
    def signal
      @cond.signal
    end
  end


  # Like Thread::Queue, but optionally bounded.
  class Franz::Queue

    # Create a new bounded Queue.
    #
    # @param max_size [Integer] set a bound (or :infinite for no bound)
    def initialize max_size=10_000, options={}
      @items           = []
      @max_size        = max_size
      @lock            = Mutex.new
      @space_available = Condition.new @lock
      @item_available  = Condition.new @lock
    end

    # Push an item onto the Queue, blocking if it's full.
    #
    # @param obj [Object] item to push
    # @param timeout [Integer] timeout in seconds to wait (or :never for none)
    # @param timeout_policy [Proc] will be called in event of a timeout
    def push obj, timeout=:never, &timeout_policy
      timeout_policy ||= -> { raise 'Push timed out' }
      wait_for_condition(@space_available, -> { !full? }, timeout, timeout_policy) do
        @items.push obj
        @item_available.signal
      end
      return self
    end

    # Pop an item off the Queue, blocking if it's empty.
    #
    # @param timeout [Integer] timeout in seconds to wait (or :never for none)
    # @param timeout_policy [Proc] will be called in event of a timeout
    #
    # @return [Object] the item we popped
    def pop timeout=:never, &timeout_policy
      timeout_policy ||= -> { nil }
      wait_for_condition(@item_available, -> { @items.any? }, timeout, timeout_policy) do
        item = @items.shift
        @space_available.signal unless full?
        item
      end
    end

    alias_method :shift, :pop

    # Is the queue empty?
    #
    # @return [Boolean]
    def empty? ; @items.empty? end

    # Is the queue full?
    #
    # @return [Boolean]
    def full?
      return false if @max_size == :infinite
      @max_size <= @items.size
    end

    # Return the list of keys
    #
    # @return [Array]
    def keys
      return @items.keys
    end

  private
    def wait_for_condition cond, predicate, timeout=:never, timeout_policy=-> { nil }
      deadline = timeout == :never ? :never : Time.now + timeout
      @lock.synchronize do
        loop do
          cond_timeout = timeout == :never ? nil : deadline - Time.now
          cond.wait(cond_timeout) if !predicate.call && cond_timeout.to_f >= 0
          if predicate.call
            return yield
          elsif deadline == :never || deadline > Time.now
            next
          else
            return timeout_policy.call
          end
        end
      end
    end
  end
end