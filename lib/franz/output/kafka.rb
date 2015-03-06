require 'thread'
require 'json'

require 'poseidon'
require 'deep_merge'


module Franz
  module Output

    # Kafka output for Franz.
    class Kafka
      @@host = Socket.gethostname # We'll apply the hostname to all events


      # Start a new output in the background. We'll consume from the input queue
      # and ship events to STDOUT.
      #
      # @param [Hash] opts options for the output
      # @option opts [Queue] :input ([]) "input" queue
      # @option opts [Queue] :output ([]) "output" configuration
      def initialize opts={}
        opts = {
          logger: Logger.new(STDOUT),
          tags: [],
          input: [],
          output: {
            flush_interval: 10,
            flush_size: 500,
            client_id: @@host,
            cluster: %w[ localhost:9092 ],
            type: 'sync',
            compression_codec: 'snappy',
            metadata_refresh_interval_ms: 600000,
            max_send_retries: 3,
            retry_backoff_ms: 100,
            required_acks: 0,
            ack_timeout_ms: 1500,
            socket_timeout_ms: 10000
          }
        }.deep_merge!(opts)

        @statz = opts[:statz] || Franz::Stats.new
        @statz.create :num_output, 0

        @logger = opts[:logger]

        @stop = false
        @foreground = opts[:foreground]

        @flush_size = opts[:output].delete :flush_size
        @flush_interval = opts[:output].delete :flush_interval

        kafka_cluster = opts[:output].delete :cluster
        kafka_client_id = opts[:output].delete :client_id
        kafka_config = opts[:output].map { |k,v| v.is_a?(String) ? v.to_sym : v }

        @kafka = Poseidon::Producer.new \
          kafka_cluster,
          kafka_client_id,
          Hash[kafka_config]

        @lock = Mutex.new
        @messages = []


        @thread = Thread.new do
          loop do
            ready_messages = []
            @lock.synchronize do
              ready_messages = @messages
              @messages = []
            end
            @kafka.send_messages ready_messages unless ready_messages.empty?
            log.debug \
              event: 'periodic flush',
              num_messages: ready_messages.size
            sleep @flush_interval
          end
        end


        @thread = Thread.new do
          until @stop
            event = opts[:input].shift

            log.trace \
              event: 'publish',
              raw: event

            payload = JSON::generate(event)
            @messages << Poseidon::MessageToSend.new(event[:type].to_s, payload)

            @statz.inc :num_output

            if @statz.get(:num_output) % @flush_size == 0
              @kafka.send_messages @messages unless @messages.empty?
              log.debug \
                event: 'flush',
                num_messages: @messages.size
              @messages = []
            end

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