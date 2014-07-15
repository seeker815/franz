require 'json'

module Franz::Config
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