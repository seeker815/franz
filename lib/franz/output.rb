require 'json'

require 'bunny'
require 'deep_merge'

module Franz

  # RabbitMQ output for Franz. You must declare an x-consistent-hash type
  # exchange, as we generate random Integers for routing keys.
  class Output

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

      @logger = opts[:logger]

      rabbit = Bunny.new opts[:output][:connection].merge \
        automatically_recover: true,
        threaded: true,
        heartbeat: 90

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
          event = opts[:input].shift
          # event[:tags] = opts[:tags] unless opts[:tags].empty?
          event.delete(:tags)
          event[:path] = event[:path].sub('/home/denimuser/seam-builds/rel', '')
          event[:path] = event[:path].sub('/home/denimuser/seam-builds/live', '')
          event[:path] = event[:path].sub('/home/denimuser/seam-builds/beta', '')
          event[:path] = event[:path].sub('/home/denimuser/builds/rel', '')
          event[:path] = event[:path].sub('/home/denimuser/builds/live', '')
          event[:path] = event[:path].sub('/home/denimuser/builds/beta', '')
          event[:path] = event[:path].sub('/home/denimuser/cobalt-builds/rel', '')
          event[:path] = event[:path].sub('/home/denimuser/cobalt-builds/live', '')
          event[:path] = event[:path].sub('/home/denimuser/cobalt-builds/beta', '')
          event[:path] = event[:path].sub('/home/denimuser/rivet-builds', '')
          event[:path] = event[:path].sub('/home/denimuser/denim/logs', '')
          event[:path] = event[:path].sub('/home/denimuser/seam/logs', '')
          event[:path] = event[:path].sub('/home/denimuser/rivet/bjn/logs', '')
          event[:path] = event[:path].sub('/home/denimuser', '')
          event[:path] = event[:path].sub('/var/log', '')
          log.trace 'publishing event=%s' % event.inspect
          exchange.publish \
            JSON::generate(event),
            routing_key: rand.rand(10_000),
            persistent: false
        end
      end

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
    end

  private
    def log ; @logger end
  end
end