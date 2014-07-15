require 'json'

# All things configuration.
module Franz::Config

  # Load a config file path into a Hash, converting to some native types where
  # appropriate (e.g. a String denoting a Regexp will become Regexp).
  #
  # @param path [String] path to a config file
  def self.load path
    config = JSON::parse File.read(path), symbolize_names: true
    config[:input][:configs].map! do |input|
      input[:multiline] = Regexp.new input[:multiline]
      input[:type] = input[:type].to_sym
      input
    end
    return config
  end
end