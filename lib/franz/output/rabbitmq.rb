require 'json'

require 'bunny'
require 'deep_merge'


# RabbitMQ output for Franz. You must declare an x-consistent-hash type
# exchange, as this output randomly generates Integers as routing keys.
class Franz::Output::RabbitMQ
  # Start a new output in the background. We'll consume from the input queue
  # and ship events to the configured RabbitMQ cluster.
  #
  # @param opts [Hash] a complex Hash for output configuration
  def initialize opts={}
    opts = {
      input: nil,
      output: {
        exchange: {
          name: 'test',
          durable: true
        },
        connection: {
          host: 'localhost',
          port: 5672
        }
      }
    }.deep_merge!(opts)

    rabbit = Bunny.new opts[:output][:connection]
    rabbit.start

    channel  = rabbit.create_channel
    exchange = opts[:output][:exchange].delete(:name)
    exchange = channel.exchange exchange, \
      opts[:output][:exchange].merge(type: 'x-consistent-hash')

    @stop = false
    @foreground = opts[:foreground]

    @thread = Thread.new do
      rand = Random.new
      until @stop
        exchange.publish \
          JSON::generate(opts[:input].shift),
          routing_key: rand.rand(1_000_000),
          persistent: false
      end
    end

    @thread.join if @foreground
  end

  # Join the background thread. Effectively only once.
  def join
    return if @foreground
    @foreground = true
    @thread.join
  end

  # Stop the output. Effectively only once.
  def stop
    return if @foreground
    @foreground = true
    @thread.kill
  end
end