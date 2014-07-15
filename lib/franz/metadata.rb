module Franz
  VERSION  = File.read(File.join(File.dirname(__FILE__), '..', '..', 'VERSION')).strip
  SUMMARY  = 'Aggregate log file events and send them elsewhere'
  AUTHOR   = 'Sean Clemmer'
  EMAIL    = 'sclemmer@bluejeans.com'
  HOMEPAGE = 'http://wiki.bluejeansnet.com/operations/franz'
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
