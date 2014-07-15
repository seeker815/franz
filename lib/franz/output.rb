require 'json'
require 'socket'

require 'bunny'
require 'deep_merge'


class Franz::Output
  @@host = Socket.gethostname

  def initialize opts={}
    opts = {
      input: nil,
      output: {
        rabbitmq: {
          exchange: {
            name: 'test',
            durable: true,
            type: 'x-consistent-hash'
          },
          connection: {
            host: 'localhost',
            port: 5672
          }
        }
      }
    }.deep_merge!(opts)

    rabbit = Bunny.new opts[:output][:rabbitmq][:connection]
    rabbit.start

    channel  = rabbit.create_channel
    exchange = opts[:output][:rabbitmq][:exchange].delete(:name)
    exchange = channel.exchange exchange, opts[:output][:rabbitmq][:exchange]

    @stop = false
    @foreground = opts[:foreground]

    @thread = Thread.new do
      rand = Random.new
      until @stop
        exchange.publish \
          JSON::generate(opts[:input].shift.merge(host: @@host)),
          persistent: false, routing_key: rand.rand(1_000_000)
      end
    end

    @thread.join if @foreground
  end

  def join
    return if @foreground
    @foreground = true
    @thread.join
  end

  def stop
    join
  end
end