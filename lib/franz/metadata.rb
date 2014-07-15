# Franz ships line-oriented log files to RabbitMQ. Think barebones logstash in
# pure Ruby with more modest compute and memory requirements.
module Franz

  # We use a VERSION file to tie into our build pipeline
  VERSION  = File.read(File.join(File.dirname(__FILE__), '..', '..', 'VERSION')).strip

  # We don't really do all that much, be humble
  SUMMARY  = 'Aggregate log file events and send them elsewhere'

  # Your benevolent dictator for life
  AUTHOR   = 'Sean Clemmer'

  # Turn here to strangle your dictator
  EMAIL    = 'sclemmer@bluejeans.com'

  # Every project deserves its own ASCII art
  ART      = <<-'EOART' % VERSION

      .--.,
    ,--.'  \  __  ,-.                 ,---,        ,----,
    |  | /\/,' ,'/ /|             ,-+-. /  |     .'   .`|
    :  : :  '  | |' | ,--.--.    ,--.'|'   |  .'   .'  .'
    :  | |-,|  |   ,'/       \  |   |  ,"' |,---, '   ./
    |  : :/|'  :  / .--.  .-. | |   | /  | |;   | .'  /
    |  |  .'|  | '   \__\/: . . |   | |  | |`---' /  ;--,
    '  : '  ;  : |   ," .--.; | |   | |  |/   /  /  / .`|
    |  | |  |  , ;  /  /  ,.  | |   | |--'  ./__;     .'
    |  : \   ---'  ;  :   .'   \|   |/      ;   |  .'
    |  |,'         |  ,     .-./'---'       `---'
    `--'            `--`---'                       v%s
  EOART
end