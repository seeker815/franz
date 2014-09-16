require 'logger'

module Franz

  # Watch works in tandem with Discover to maintain a list of known files and
  # their status. Events are generated when a file is created, destroyed, or
  # modified (including appended, truncated, and replaced).
  class Watch

    # Start a new Watch thread in the background.
    #
    # @param [Hash] opts options for the watch
    # @option opts [Queue] :discoveries ([]) "input" queue of discovered paths
    # @option opts [Queue] :deletions ([]) "output" queue of deleted paths
    # @option opts [Queue] :watch_events ([]) "output" queue of file events
    # @option opts [Fixnum] :watch_interval (1) seconds between watch rounds
    # @option opts [Hash<Path,State>] :stats ([]) internal "stats" state
    # @option opts [Logger] :logger (Logger.new(STDOUT)) logger to use
    def initialize opts={}
      @discoveries  = opts[:discoveries]  || []
      @deletions    = opts[:deletions]    || []
      @watch_events = opts[:watch_events] || []

      @watch_interval = opts[:watch_interval] || 10
      @stats          = opts[:stats]          || Hash.new
      @logger         = opts[:logger]         || Logger.new(STDOUT)

      # Make sure we're up-to-date
      stats.keys.each do |path|
        begin
          stat   = File.stat(path)
          size   = stat.size
          cursor = opts[:full_state][path][:cursor]
          if cursor.nil?
            # nop
          elsif size < cursor
            enqueue name: :truncated, path: path, size: size
          elsif size > cursor
            enqueue name: :appended, path: path, size: size
          end
        rescue KeyError
          log.error 'Erm, shouldna got here'
        rescue Errno::ENOENT
          @stats.delete(path)
          enqueue :deleted, path
          deleted << path
        end
      end

      @stop = false

      log.debug 'watch: discoveries=%s deletions=%s watch_events=%s' % [
        @discoveries, @deletions, @watch_events
      ]

      @thread = Thread.new do
        until @stop
          until discoveries.empty?
            @stats[discoveries.shift] = nil
          end
          watch.each do |deleted|
            @stats.delete deleted
            deletions.push deleted
          end
          sleep watch_interval
        end
      end

      log.debug 'started watch'
    end

    # Stop the Watch thread. Effectively only once.
    #
    # @return [Hash] internal "stats" state
    def stop
      return state if @stop
      @stop = true
      @thread.kill
      log.debug 'stopped watch'
      return state
    end

    # Return the internal "stats" state
    def state
      return @stats.dup
    end

  private
    attr_reader :discoveries, :deletions, :watch_events, :watch_interval, :stats

    def log ; @logger end

    def enqueue name, path, size=nil
      log.trace 'enqueue: name=%s path=%s size=%s' % [
        name.inspect, path.inspect, size.inspect
      ]
      watch_events.push name: name, path: path, size: size
    end

    def watch
      deleted = []
      stats.keys.each do |path|
        old_stat    = stats[path]
        stat        = stat_for path
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