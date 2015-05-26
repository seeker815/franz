require 'json'

require 'deep_merge'


module Franz
  module Output

    # STDOUT output for Franz.
    class Device

      # Start a new output in the background. We'll consume from the input queue
      # and ship events to STDOUT.
      #
      # @param [Hash] opts options for the output
      # @option opts [Queue] :input ([]) "input" queue
      def initialize opts={}
        opts = {
          logger: Logger.new(STDOUT),
          tags: [],
          input: [],
          output: '/dev/stdout'
        }.deep_merge!(opts)

        @statz = opts[:statz] || Franz::Stats.new
        @statz.create :num_output, 0

        @device = File.open(opts[:output], 'w')
        @logger = opts[:logger]

        @stop = false
        @foreground = opts[:foreground]

        @thread = Thread.new do
          until @stop
            event = opts[:input].shift

            log.trace \
              event: 'publish',
              raw: event

            @device.puts JSON::generate(event)

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
        @device.close
        log.info event: 'output stopped'
      end

    private
      def log ; @logger end
    end
  end
end