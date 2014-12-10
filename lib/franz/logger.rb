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

  # A colorful JSON logger for Franz.
  class Logger < Logger
    # Maps each log level to a unique combination of fore- and background colors
    SEVERITY_COLORS = {
      'debug' => [ :blue,    :default ],
      'info'  => [ :green,   :default ],
      'warn'  => [ :yellow,  :default ],
      'error' => [ :red,     :default ],
      'fatal' => [ :red,     :black   ],
      'trace' => [ :magenta, :default ]
    }

    # Create a new, colorful logger.
    #
    # @param debug [Boolean] enable DEBUG level logs
    # @param out [File] output destination for logs
    def initialize debug=false, trace=false, out=nil
      colorize = out.nil?
      out ||= $stdout
      super out, 5, 104857600 # Keep max five logs at 100 [MiB] each
      format colorize
      @trace = true if trace
      self.level = ::Logger::INFO
      self.level = ::Logger::DEBUG if debug
    end

  private
    def format colorize
      self.formatter = proc do |severity, datetime, _, message|

        message = { message: message } unless message.is_a? Hash

        event = {
          severity: severity.downcase!,
          timestamp: datetime.iso8601(6),
          marker: File::basename(caller[4])
        }.merge(message)

        if colorize # console output
          event = JSON::pretty_generate(event) + "\n"
          event.colorize \
            color: SEVERITY_COLORS[severity][0],
            background: SEVERITY_COLORS[severity][1]

        else # logging to file
          event = JSON::generate(event) + "\n"
        end
      end
    end
  end
end