module Franz
  class InputConfig
    attr_reader :configs

    def initialize configs
      @configs = configs
      @types = Hash.new
    end

    def config path
      t = type(path)
      configs.select { |c| c[:type] == t }.shift
    end

    def json? path
      begin
        return config(path)[:json?]
      rescue
        return false
      end
    end

    def drop? path, message
      begin
        drop = config(path)[:drop]
      rescue
        return true # No config found, drop it!
      end
      if drop
        drop = drop.is_a?(Array) ? drop : [ drop ]
        drop.each do |pattern|
          return true if message =~ pattern
        end
      end
      return false
    end

    def type path
      begin
        @types.fetch path
      rescue KeyError
        configs.each do |config|
          type = config[:type] if config[:includes].any? { |glob|
            included = File.fnmatch? glob, path
            excludes = !config[:excludes].nil?
            excluded = excludes && config[:excludes].any? { |exlude|
              File.fnmatch? exlude, File::basename(path)
            }
            included && !excluded
          }
          unless type.nil?
            @types[path] = type
            return type
          end
        end
        log.warn \
          event: 'type unknown',
          file: path
        @types[path] = nil
        return nil
      end
    end
  end
end