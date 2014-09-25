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

      @play_catchup   = opts[:play_catchup?]  || true
      @watch_interval = opts[:watch_interval] || 10
      @stats          = opts[:stats]          || Hash.new
      @logger         = opts[:logger]         || Logger.new(STDOUT)

      @num_skipped = 0
      @skip_interval = 15 * 60 # 15 minutes

      # Make sure we're up-to-date by rewinding our old stats to our cursors
      stats.keys.each do |path|
        stats[path][:size] = opts[:full_state][path][:cursor] || 0
      end if @play_catchup

      @stop = false
      @thread = Thread.new do
        stale_updated = Time.now - 2 * @skip_interval

        until @stop
          started = Time.now
          until discoveries.empty?
            @stats[discoveries.shift] = nil
          end

          skip_stale = true
          if stale_updated < started - @skip_interval
            skip_stale = false
            stale_updated = Time.now
          end

          watch(skip_stale).each do |deleted|
            @stats.delete deleted
            deletions.push deleted
          end

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
      log.debug \
        event: 'watch',
        skip_stale: skip_stale
      deleted = []
      skip_past = Time.now - @skip_interval

      stats.keys.each do |path|
        # Hacks for logs we've removed
        next if File.basename(path) =~ /^rtpstat/
        next if File.basename(path) == 'zuora.log'

        old_stat = stats[path]

        next if skip_stale \
        && old_stat \
        && old_stat[:mtime] \
        && old_stat[:mtime] < skip_past

        stat = stat_for path
        stats[path] = stat

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