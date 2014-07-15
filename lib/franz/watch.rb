require 'logger'

module Franz

  # Watch works in tandem with Discover to maintain a list of known files and
  # their status. Events are generated when a file is created, destroyed, or
  # modified (including appended, truncated, and replaced).
  class Watch

    # Start a new Watch thread in the background.
    #
    # @param opts [Hash] a complex Hash for tail configuration
    def initialize opts={}
      @discoveries  = opts[:discoveries]  || []
      @deletions    = opts[:deletions]    || []
      @watch_events = opts[:watch_events] || []
      @interval     = opts[:interval]     || 1
      @stats        = opts[:stats]        || Hash.new
      @logger       = opts[:logger]       || Logger.new(STDOUT)

      # Need to resend old events to make sure Tail catches up
      stats.each do |path, old_stat|
        watch_events.push name: :appended, path: path, size: old_stat[:size]
      end

      @stop = false

      @thread = Thread.new do
        until @stop
          until discoveries.empty?
            d = discoveries.pop
            @stats[d] = nil
          end
          watch.each do |deleted|
            @stats.delete deleted
            deletions.push deleted
          end
          sleep interval
        end
      end
    end

    # Stop the Watch thread. Effectively only once.
    #
    # @return [Hash] internal "stats" state
    def stop
      return @stats if @stop
      @stop = true
      @thread.join
      return @stats
    end

  private
    attr_reader :discoveries, :deletions, :watch_events, :interval, :stats

    def log ; @logger end

    def enqueue name, path, size=nil
      log.debug 'enqueue: name=%s path=%s size=%s' % [
        name.inspect, path.inspect, size.inspect
      ]
      watch_events.push name: name, path: path, size: size
    end

    def watch
      deleted = []
      stats.each do |path, old_stat|
        stat = stat_for path
        stats[path] = stat

        if file_created? old_stat, stat
          enqueue :created, path
        elsif file_deleted? old_stat, stat
          enqueue :deleted, path
          deleted << path
        end

        if file_replaced? old_stat, stat
          enqueue :replaced, path, stat[:size]
        elsif file_appended? old_stat, stat
          enqueue :appended, path, stat[:size]
        elsif file_truncated? old_stat, stat
          enqueue :truncated, path, stat[:size]
        end
      end
      return deleted
    end



    # Perform a file stat and return a simplified version.
    #
    # @param path [String] file path to examine
    def stat_for path
      return begin
        stat = File::Stat.new(path)
        {
          inode: {
            ino: stat.ino,
            maj: stat.dev_major,
            min: stat.dev_minor
          },
          size: stat.size
        }
      rescue Errno::ENOENT
        nil
      end
    end

    # Grab only the inode from a stat (or nil if the stat is nil).
    #
    # @param stat [Stat] stat to inspect
    def inode_for stat
      return nil if stat.nil?
      return stat[:inode].to_a
    end

    # Detect whether the file was created.
    #
    # @param old_stat [Stat] stat before some change
    # @param new_stat [Stat] stat after some change
    def file_created? old_stat, new_stat
      return !new_stat.nil? && old_stat.nil?
    end

    # Detect whether the file was deleted.
    #
    # @param old_stat [Stat] stat before some change
    # @param new_stat [Stat] stat after some change
    def file_deleted? old_stat, new_stat
      return new_stat.nil? && !old_stat.nil?
    end

    # Detect whether the file was replaced (e.g. inode changed).
    #
    # @param old_stat [Stat] stat before some change
    # @param new_stat [Stat] stat after some change
    def file_replaced? old_stat, new_stat
      return false if new_stat.nil?
      return false if old_stat.nil?
      return inode_for(new_stat) != inode_for(old_stat)
    end

    # Detect whether the file was truncated (e.g. rotated).
    #
    # @param old_stat [Stat] stat before some change
    # @param new_stat [Stat] stat after some change
    def file_truncated? old_stat, new_stat
      return false if new_stat.nil?
      return false if old_stat.nil?
      return new_stat[:size] < old_stat[:size]
    end

    # Detect whether the file was appended.
    #
    # @param old_stat [Stat] stat before some change
    # @param new_stat [Stat] stat after some change
    def file_appended? old_stat, new_stat
      return false if new_stat.nil?
      return new_stat[:size] > 0 if old_stat.nil?
      return new_stat[:size] > old_stat[:size]
    end
  end
end