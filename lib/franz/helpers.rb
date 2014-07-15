# Mostly provides a few abstractions for working with file stats.
module Franz::Helpers

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