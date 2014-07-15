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

    @stop = false
    @foreground = opts[:foreground]

    @t = Thread.new do
      rand = Random.new
      until @stop
        exchange.publish \
          JSON::generate(input.shift.merge(host: @@host)),
          persistent: false, routing_key: rand.rand(1_000_000)
      end
    end

    @t.join if @foreground
  end

  def join
    return if @foreground
    @foreground = true
    @t.join
  end

  def stop
    join
  end
end