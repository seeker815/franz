# Franz ships line-oriented log files to RabbitMQ. Think barebones logstash in
# pure Ruby with more modest compute and memory requirements.
module Franz

  # We use a VERSION file to tie into our build pipeline
  VERSION  = File.read(File.join(File.dirname(__FILE__), '..', '..', 'VERSION')).strip

  # We don't really do all that much, be humble
  SUMMARY  = 'Aggregate log file events and send them elsewhere'

  # Like the MIT license, but even simpler
  LICENSE  = 'ISC'

  # Where you should look first
  HOMEPAGE = 'https://github.com/sczizzo/franz'

  # Your benevolent dictator for life
  AUTHOR   = 'Sean Clemmer'

  # Turn here to strangle your dictator
  EMAIL    = 'sclemmer@bluejeans.com'

  # Bundled extensions
  TRAVELING_RUBY_VERSION = '20150210-2.1.5'
  SNAPPY_VERSION = '0.0.11'
  EM_VERSION = '1.0.5'

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