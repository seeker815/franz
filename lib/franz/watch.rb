require 'set'

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

      @num_skipped = 0

      @stop = false
      @thread = Thread.new do
        stale_updated = 0

        until @stop
          discoveries_size = discoveries.size
          deletions_size = deletions.size
          watch_size = watch_events.size
          stats_size = stats.keys.size
          cp_started = Time.now

          until discoveries.empty?
            @stats[discoveries.shift] = nil
          end
          cp_handled_discoveries = Time.now

          skip_stale = true
          if stale_updated < cp_started.to_i - 10 * 60
            log.warn \
              event: 'watch statting stale',
              last_statted: stale_updated
            skip_stale = false
            stale_updated = Time.now.to_i
          end

          deletions = watch(skip_stale)
          cp_watched = Time.now

          deletions.each do |deleted|
            @stats.delete deleted
            deletions.push deleted
          end
          cp_handled_deletions = Time.now

          elapsed_total = cp_handled_deletions - cp_started
          elapsed_handling_deletions = cp_handled_deletions - cp_watched
          elapsed_in_watch = cp_watched - cp_handled_discoveries
          elapsed_handling_discoveries = cp_handled_discoveries - cp_started

          log.trace \
            event: 'watch finished',
            elapsed_total: elapsed_total,
            elapsed_handling_discoveries: elapsed_handling_discoveries,
            elapsed_in_watch: elapsed_in_watch,
            elapsed_handling_deletions: elapsed_handling_deletions,
            discoveries_size_before: discoveries_size,
            discoveries_size_after: discoveries.size,
            deletions_size_before: deletions_size,
            deletions_size_after: deletions.size,
            watch_events_size_before: watch_size,
            watch_events_size_after: watch_events.size,
            stats_size_before: stats_size,
            stats_size_after: stats.keys.size,
            skipped: @num_skipped

          sleep watch_interval
        end
      end

      log.debug \
        event: 'watch started',
        discoveries: discoveries,
        deletions: deletions,
        watch_events: watch_events,
        watch_interval: watch_interval
    end

    # Stop the Watch thread. Effectively only once.
    #
    # @return [Hash] internal "stats" state
    def stop
      return state if @stop
      @stop = true
      @thread.kill
      log.debug event: 'watch stopped'
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
      watch_events.push name: name, path: path, size: size
    end

    def watch skip_stale=true
      deleted = []
      keys = stats.keys
      size = keys.size
      i = 0

      cp_started_watch = Time.now
      fifteen_minutes_ago = Time.now - 15 * 60
      @num_skipped = 0

      keys.each do |path|
        i += 1
        old_stat = stats[path]

        if skip_stale \
        && old_stat \
        && old_stat[:mtime] \
        && old_stat[:mtime] < fifteen_minutes_ago
          @num_skipped += 1
          next
        end

        cp_started_stat = Time.now
        stat = stat_for path
        stats[path] = stat
        cp_statted = Time.now

        if file_created? old_stat, stat
          # enqueue :created, path
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
        cp_enqueued = Time.now

        elapsed_total = cp_enqueued - cp_started_watch
        elapsed_statting = cp_enqueued - cp_started_stat
        elapsed_in_enqueue = cp_enqueued - cp_statted
        elapsed_in_stat = cp_statted - cp_started_stat

        log.trace \
          event: 'watch stat finished',
          path: path,
          elapsed_total: elapsed_total,
          elapsed_statting: elapsed_statting,
          elapsed_in_stat: elapsed_in_stat,
          elapsed_in_enqueue: elapsed_in_enqueue,
          stat_num: i,
          stat_size: size,
          watch_size: watch_events.size,
          skipped: @num_skipped
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
          size: stat.size,
          mtime: stat.mtime
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