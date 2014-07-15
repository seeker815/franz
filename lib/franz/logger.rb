require 'logger'
require 'time'

require 'colorize'


module Franz::Logger
  SEVERITY_COLORS = {
    'DEBUG' => [ :blue,   :default ],
    'INFO'  => [ :green,  :default ],
    'WARN'  => [ :yellow, :default ],
    'ERROR' => [ :red,    :default ],
    'FATAL' => [ :red,    :black   ]
  }

  def self.spawn level=::Logger::INFO, file=STDOUT
    logger           = ::Logger.new file
    logger.level     = level
    logger.formatter = proc do |severity, datetime, _, msg|
      if level == 1
        msg.to_s.colorize(
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
          msg
        ]
      end
    end
    return logger
  end
end