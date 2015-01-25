require 'thread'
require 'logger'


module Franz
  class Stats

    def initialize opts={}
      @logger = opts[:logger] || Logger.new(STDOUT)
      @interval = opts[:interval] || 300
      @stats = Hash.new
      @lock = Mutex.new
      @t = Thread.new do
        loop do
          sleep @interval
          report
          reset
        end
      end
    end


    def stop
      return state if @stop
      @stop = true
      @t.stop
      log.info event: 'stats stopped'
      return nil
    end


    def create name, default=nil
      with_lock do
        stats[name] = Hash.new { |h,k| h[k] = default }
      end
    end

    def delete name
      with_lock do
        stats.delete name
      end
    end

    def inc name, by=1
      with_lock do
        stats[name][:val] += by
      end
    end

    def dec name, by=1
      with_lock do
        stats[name][:val] -= by
      end
    end

    def set name, to
      with_lock do
        stats[name][:val] = to
      end
    end

    def get name
      with_lock do
        stats[name][:val]
      end
    end

  private
    attr_reader :stats

    def log ; @logger end

    def with_lock &block
      @lock.synchronize do
        yield
      end
    end

    def report
      ready_stats = with_lock do
        stats.map { |k,vhash| [ k, vhash[:val] ] }
      end
      log.fatal \
        event: 'stats',
        interval: @interval,
        stats: Hash[ready_stats]
    end

    def reset
      with_lock do
        stats.keys.each do |k|
          stats[k].delete :val
        end
      end
    end
  end
end