require "thread"

module Franz
  class Condition
    def initialize(lock)
      @lock = lock
      @cv   = ConditionVariable.new
    end

    def wait(timeout=nil)
      @cv.wait(@lock, timeout)
    end

    def signal
      @cv.signal
    end
  end

  class Queue
    def initialize(max_size=4096, options={}) # also max_size=:infinite
      @items           = []
      @max_size        = max_size
      @lock            = options.fetch(:lock) { Mutex.new }
      @space_available = options.fetch(:space_available_condition) {
        Condition.new(@lock)
      }
      @item_available  = options.fetch(:item_available_condition) {
        Condition.new(@lock)
      }
    end

    def push(obj, timeout=:never, &timeout_policy)
      timeout_policy ||= -> do
        raise "Push timed out"
      end
      wait_for_condition(
        @space_available,
        ->{!full?},
        timeout,
        timeout_policy) do

        @items.push(obj)
        @item_available.signal
      end
    end

    def pop(timeout = :never, &timeout_policy)
      timeout_policy ||= ->{nil}
      wait_for_condition(
        @item_available,
        ->{@items.any?},
        timeout,
        timeout_policy) do

        item = @items.shift
        @space_available.signal unless full?
        item
      end
    end

    alias_method :shift, :pop

    def empty?
      @items.empty?
    end

  private
    def full?
      return false if @max_size == :infinite
      @max_size <= @items.size
    end

    def wait_for_condition(
        cv, condition_predicate, timeout=:never, timeout_policy=->{nil})
      deadline = timeout == :never ? :never : Time.now + timeout
      @lock.synchronize do
        loop do
          cv_timeout = timeout == :never ? nil : deadline - Time.now
          if !condition_predicate.call && cv_timeout.to_f >= 0
            cv.wait(cv_timeout)
          end
          if condition_predicate.call
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