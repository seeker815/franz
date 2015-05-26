require 'net/http'
require 'thread'
require 'fiber'
require 'json'

require 'deep_merge'


module Franz
  module Output

    # HTTP output for Franz.
    class HTTP
      # Start a new output in the background. We'll consume from the input queue
      # and ship events via HTTP.
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
            server: 'http://localhost:3000',
            flush_size: 500,
            flush_interval: 10
          }
        }.deep_merge!(opts)

        @statz = opts[:statz] || Franz::Stats.new
        @statz.create :num_output, 0

        @logger = opts[:logger]

        @stop = false
        @foreground = opts[:foreground]

        server = opts[:output].delete :server
        @uri   = URI(server)
        open_uri

        @flush_size = opts[:output][:flush_size]
        @flush_interval = opts[:output][:flush_interval]
        @lock = Mutex.new
        @messages = []

        Thread.new do
          until @stop
            @lock.synchronize do
              flush_messages true
            end
            sleep @flush_interval
          end
        end

        @thread = Thread.new do
          until @stop
            event = JSON::generate(opts[:input].shift)
            @lock.synchronize do
              enqueue event
            end

            log.trace \
              event: 'publish',
              raw: event
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

      def open_uri
        @http = Net::HTTP.new(@uri.host, @uri.port)
      end

      def enqueue event
        @messages << event
        flush_messages
      end

      def flush_messages force=false
        size = @messages.length
        return if size.zero?
        if force || size >= @flush_size
          emit @messages.join("\n")
          @statz.inc :num_output, size
          @messages.clear
        end
      end

      def emit body
        request = Net::HTTP::Post.new(@uri)
        request.body = body
        @http.request(request)
      rescue EOFError, Errno::ECONNREFUSED, Errno::EPIPE
        log.warn event: 'output dropped'
        open_uri
        sleep 1
        retry
      end
    end
  end
end