require 'json'

require 'bunny'
require 'deep_merge'


module Franz
  module Output

    # RabbitMQ output for Franz. You must declare an x-consistent-hash type
    # exchange, as we generate random Integers for routing keys.
    class RabbitMQ

      # Start a new output in the background. We'll consume from the input queue
      # and ship events to the configured RabbitMQ cluster.
      #
      # @param [Hash] opts options for the output
      # @option opts [Queue] :input ([]) "input" queue
      # @option opts [Hash] :output ({}) "output" configuration
      def initialize opts={}
        opts = {
          logger: Logger.new(STDOUT),
          tags: [],
          input: [],
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

        @statz = opts[:statz] || Franz::Stats.new
        @statz.create :num_output, 0

        @logger = opts[:logger]

        rabbit = Bunny.new opts[:output][:connection].merge({
          network_recovery_interval: 10.0,
          continuation_timeout: 10_000,
          threaded: false,
          logger: @logger
        })

        rabbit.start

        channel  = rabbit.create_channel
        exchange = opts[:output][:exchange].delete(:name)
        exchange = channel.exchange exchange, \
          { type: 'x-consistent-hash' }.merge(opts[:output][:exchange])

        @stop = false
        @foreground = opts[:foreground]

        @thread = Thread.new do
          rand = Random.new
          until @stop
            event = opts[:input].shift

            unless opts[:tags].empty?
              event['tags'] ||= []
              event['tags']  += opts[:tags]
            end

            log.debug \
              event: 'publish',
              raw: event

            exchange.publish \
              JSON::generate(event),
              routing_key: rand.rand(10_000),
              persistent: false

            @statz.inc :num_output
          end
        end

        log.info event: 'output started'

        @thread.join if @foreground
      end

      # Join the Output thread. Effectively only once.
      def join
        return if @foreground
        @foreground = true
        @thread.join
      end

      # Stop the Output thread. Effectively only once.
      def stop
        return if @foreground
        @foreground = true
        @thread.kill
        log.info event: 'output stopped'
      end

    private
      def log ; @logger end
    end
  end
end