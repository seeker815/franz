module Franz
  class InputConfig
    attr_reader :configs

    def initialize configs, logger=nil
      @logger  = logger || Logger.new(STDOUT)
      @configs = configs
      @configs.map! do |c|
        normalized_config c
      end
      @types = Hash.new
      @drop  = Hash.new
      @keep  = Hash.new
    end

    def config path
      t = type(path)
      configs.select { |c| c[:type] == t }.shift
    end

    def json? path
      config(path)[:json?]
    rescue
      false
    end

    def keep? path, message
      patterns = keeps_for(path)
      return true if patterns.nil?
      return true if patterns.empty?
      apply_patterns patterns, message
    end

    def drop? path, message
      patterns = drops_for(path)
      return true if patterns.nil?
      return false if patterns.empty?
      apply_patterns patterns, message
    end

    def type path
      @types.fetch path
    rescue KeyError
      configs.each do |config|
        type = config[:type] if config[:includes].any? { |glob|
          included = File.fnmatch? glob, path, File::FNM_EXTGLOB
          excludes = !config[:excludes].nil?
          excluded = excludes && config[:excludes].any? { |exlude|
            File.fnmatch? exlude, File::basename(path), File::FNM_EXTGLOB
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
    end


  private
    def log ; @logger end

    def normalized_config config
      config[:keep] = realize_regexps config[:keep]
      config[:drop] = realize_regexps config[:drop]
      config
    end

    def realize_regexps ps
      return [] if ps.nil?
      ps = ps.is_a?(Array) ? ps : [ ps ]
      ps.map do |pattern|
        Regexp.new pattern
      end
    end

    def apply_patterns patterns, message
      return true if patterns.nil?
      patterns.each do |pattern|
        return true if message =~ pattern
      end
      return false
    end

    def drops_for path
      patterns_for path, :drop, @drop
    end

    def keeps_for path
      patterns_for path, :keep, @keep
    end

    def patterns_for path, kind, memo
      memo.fetch path
    rescue KeyError
      c = config(path)
      k = c ? c[kind] : []
      memo[path] = k
    end

  end
end