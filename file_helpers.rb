module FileHelpers
private
  def file_created? old_stat, new_stat
    return !new_stat.nil? && old_stat.nil?
  end

  def file_deleted? old_stat, new_stat
    return new_stat.nil? && !old_stat.nil?
  end

  def file_replaced? old_stat, new_stat
    return false if new_stat.nil?
    return false if old_stat.nil?
    return inode_for(new_stat) != inode_for(old_stat)
  end

  def file_truncated? old_stat, new_stat
    return false if new_stat.nil?
    return false if old_stat.nil?
    return new_stat[:size] < old_stat[:size]
  end

  def file_appended? old_stat, new_stat
    return false if new_stat.nil?
    return new_stat[:size] > 0 if old_stat.nil?
    return new_stat[:size] > old_stat[:size]
  end

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

  def inode_for stat
    return nil if stat.nil?
    return stat[:inode].to_a
  end
end