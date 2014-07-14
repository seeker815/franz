require 'json'
require 'thread'
require 'socket'

require 'bunny'


class Franz::Output
  @@host = Socket.gethostname

  def initialize opts={}
    input = opts[:input] || Queue.new
    rabbit = Bunny.new
    rabbit.start
    channel   = rabbit.create_channel
    exchange = channel.exchange 'test', \
      :durable => true, :type => 'x-consistent-hash'

    t = Thread.new do
      rand = Random.new
      loop do
        exchange.publish \
          JSON::generate(input.shift.merge(host: @@host)),
          persistent: false, routing_key: rand.rand(1_000_000)
      end
    end

    t.join if opts[:foreground]
  end
end