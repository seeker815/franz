require 'logger'
require 'time'

require 'colorize'

module Franz

  # Extending the Logger with TRACE capabilities
  class ::Logger
    SEV_LABEL << 'TRACE'
    TRACE = SEV_LABEL.index('TRACE') # N.B. TRACE is above other levels

    # Send a TRACE-level log line
    def trace progname, &block
      add TRACE, nil, progname, &block if @trace
    end
  end

  # A powerful, colorful logger for Franz.
  class Logger < Logger
    # Maps each log level to a unique combination of fore- and background colors
    SEVERITY_COLORS = {
      'DEBUG' => [ :blue,    :default ],
      'INFO'  => [ :green,   :default ],
      'WARN'  => [ :yellow,  :default ],
      'ERROR' => [ :red,     :default ],
      'FATAL' => [ :red,     :black   ],
      'TRACE' => [ :magenta, :default ]
    }

    # Create a new, colorful logger.
    #
    # @param debug [Boolean] enable DEBUG level logs
    # @param out [File] output destination for logs
    def initialize debug=false, trace=false, out=nil
      colorize = out.nil?
      out ||= $stdout
      super out
      format colorize
      @trace = true if trace
      self.level = ::Logger::INFO
      self.level = ::Logger::DEBUG if debug
    end

  private
    def format colorize
      short_format = "%s\n"
      long_format  = "%s [%s] %s -- %s\n"

      self.formatter = proc do |severity, datetime, _, message|
        if colorize
          if level == 1
            event = { timestamp: Time.now.iso8601(6) }.merge(message)
            JSON::generate(event).colorize(
              color: SEVERITY_COLORS[severity.to_s][0],
              background: SEVERITY_COLORS[severity.to_s][1]
            ) + "\n"
          else
            long_format.colorize(
              color: SEVERITY_COLORS[severity.to_s][0],
              background: SEVERITY_COLORS[severity.to_s][1]
            ) % [
              severity,
              datetime.iso8601(6),
              File::basename(caller[4]),
              message
            ]
          end
        else # plain
          if level == 1
            event = { timestamp: Time.now.iso8601(6) }.merge(message)
            JSON::generate(event) + "\n"
          else
            long_format % [
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
end