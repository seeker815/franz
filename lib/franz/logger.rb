require 'logger'
require 'time'

require 'colorize'

module Franz

  # A powerful, colorful logger for Franz.
  class Logger < Logger

    # Maps each log level to a unique combination of fore- and background colors
    SEVERITY_COLORS = {
      'DEBUG' => [ :blue,   :default ],
      'INFO'  => [ :green,  :default ],
      'WARN'  => [ :yellow, :default ],
      'ERROR' => [ :red,    :default ],
      'FATAL' => [ :red,    :black   ]
    }

    # Create a new, colorful logger.
    #
    # @param debug [Boolean] enable DEBUG level logs
    # @param out [File] output destination for logs
    def initialize debug=false, out=$stdout
      super out
      colorize
      self.level = ::Logger::INFO
      self.level = ::Logger::DEBUG if debug
    end

  private
    def colorize
      self.formatter = proc do |severity, datetime, _, message|
        if level == 1
          message.to_s.colorize(
            color: SEVERITY_COLORS[severity.to_s][0],
            background: SEVERITY_COLORS[severity.to_s][1]
          ) + "\n"
        else
          "%s [%s] %s -- %s\n".colorize(
            color: SEVERITY_COLORS[severity.to_s][0],
            background: SEVERITY_COLORS[severity.to_s][1]
          ) % [
            severity,
            datetime.iso8601(6),
            File::basename(caller[4]),
            message
          ]
        end
      end
    end
  end
end