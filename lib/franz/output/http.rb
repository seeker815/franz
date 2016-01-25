require 'net/http'
require 'net/https'
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
            flush_interval: 10,
            ssl: {
              cert_file: nil,
              key_file: nil,
              ca_file: nil,
              verify_mode: nil
            }
          }
        }.deep_merge!(opts)

        @statz = opts[:statz] || Franz::Stats.new
        @statz.create :num_output, 0

        @logger = opts[:logger]

        @stop = false
        @foreground = opts[:foreground]

        server = opts[:output].delete :server
        @uri   = URI(server)
        @ssl   = if @uri.scheme =~ /https/
          opts[:output].delete :ssl
        end
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
            event = opts[:input].shift

            unless opts[:tags].empty?
              event['tags'] ||= []
              event['tags']  += opts[:tags]
            end

            payload = JSON::generate event
            @lock.synchronize do
              enqueue payload
            end

            log.debug \
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

        if @ssl
          @http.use_ssl = true

          if cert_file = @ssl['cert_file']
            cert = File.read cert_file
            @http.cert = OpenSSL::X509::Certificate.new(cert)
          end

          if key_file = @ssl['key_file']
            key = File.read key_file
            @http.key = OpenSSL::PKey::RSA.new(key)
          end

          if @ssl['ca_file']
            @http.ca_file = @ssl['ca_file']
          end

          case @ssl['verify_mode']
          when 'verify_peer'
            @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          when 'verify_none'
            @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          when 'verify_client_once'
            @http.verify_mode = OpenSSL::SSL::VERIFY_CLIENT_ONCE
          when 'verify_fail_if_no_peer_cert'
            @http.verify_mode = OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
          when nil
          else
            raise 'Invalid "verify_mode" specified'
          end
        end
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