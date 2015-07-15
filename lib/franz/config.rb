require 'json'

module Franz

  # All things configuration.
  class Config

    # Load a config file path into a Hash, converting to some native types where
    # appropriate (e.g. a String denoting a Regexp will become Regexp).
    #
    # @param path [String] path to a config file
    #
    # @return [Hash] config compiled into a native Hash
    def self.new path
      config = JSON::parse File.read(path), symbolize_names: true
      config = {
        input: { configs: [] },
        output: {}
      }.deep_merge!(config)
      config[:input][:configs].map! do |input|
        input[:multiline] = Regexp.new input[:multiline] if input.has_key?(:multiline)
        input[:type] = input[:type].to_sym
        input
      end
      return config
    end
  end
end