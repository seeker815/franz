# Franz ![Version](https://img.shields.io/gem/v/franz.svg?style=flat-square)

Franz ships line-oriented log files to [RabbitMQ](http://www.rabbitmq.com/).
Think barebones [logstash](http://logstash.net/) in pure Ruby with more modest
compute and memory requirements.

This is really to avoid the JVM tax, but you probably still want logstash agents
doing the bulk of the log processing. Using this setup, RabbitMQ and logstash
may be scaled and restarted independently, so new configurations may be applied
without interrupting those precious log hosts.

Even so, Franz was designed to be interruped. Before exiting, Franz keeps a log
of checkpoints, which are used to restore application state in the event of a
crash.

He's also got a couple of improvements over logstash. Let's discuss!


## Improvements

First let me say logstash is an awesome hunk of software thanks to the hard
work of Jordan Sissel and the entire logstash community.

### Multiline Flush

Anyone familiar with multiline codecs and filters in logstash is familiar with
the multiline flush issue: You finish writing your log file, you close it and
wait for it to make it through logstash, but hold up. Where's the last line?
That's right, stuck. Because logstash is expecting a steady stream of events and
that last one is being buffered so logstash can decide whether its a multiline
event. Yup, there's an outstanding issue: [LOGSTASH-271](https://logstash.jira.com/browse/LOGSTASH-271).
Yup, there's a fix: [Pull #1260](https://github.com/elasticsearch/logstash/pull/1260).
But it's not yet officially sanctioned. Such is life. At any rate, you don't
have to deal with this issue in Franz, he flushes inactive buffers after a time.
Easy-peasy, lemon-squeezy.

### File Hande-ing

Now I'm not actually sure this issue affects logstash proper, but it's one you
might face if you decide to write your own, so here goes: If you're tailing a
bunch of files and you never let go of their file handles, you might very well
exhaust your ulimit after running for a while. Because Franz is designed to be
a daemon, he only opens file handles when necessary.

### Sequential Identifiers

Okay one last feature: Every log event is assigned a sequential identifier
according to its path (and implicitly, host) in the `@seq` field. This is useful
if you expect your packets to get criss-crossed and you want to reconstruct the
events in order without relying on timestamps, which you shouldn't.


## Usage, Configuration &c.

### Installation

You can build a gem from this repository, or use RubyGems:

    $ gem install franz

### Usage

Just call for help!

    $ franz --help

          .--.,
        ,--.'  \  __  ,-.                 ,---,        ,----,
        |  | /\/,' ,'/ /|             ,-+-. /  |     .'   .`|
        :  : :  '  | |' | ,--.--.    ,--.'|'   |  .'   .'  .'
        :  | |-,|  |   ,'/       \  |   |  ,"' |,---, '   ./
        |  : :/|'  :  / .--.  .-. | |   | /  | |;   | .'  /
        |  |  .'|  | '   \__\/: . . |   | |  | |`---' /  ;--,
        '  : '  ;  : |   ," .--.; | |   | |  |/   /  /  / .`|
        |  | |  |  , ;  /  /  ,.  | |   | |--'  ./__;     .'
        |  : \   ---'  ;  :   .'   \|   |/      ;   |  .'
        |  |,'         |  ,     .-./'---'       `---'
        `--'            `--`---'                       v2.2.0


    Aggregate log file events and send them elsewhere

    Usage: franz [<options>]

    Options:
      --config, -c <s>:   Configuration file to use
           --debug, -d:   Enable debugging output
         --log, -l <s>:   Log to file, not STDOUT
         --version, -v:   Print version and exit
            --help, -h:   Show this message

### Configuration

It's kinda like a JSON version of the Logstash config language:

    {
      // The asterisk will be replaced with a Unix timestamp
      "checkpoint": "/etc/franz/franz.*.db",
      "checkpoint_interval": 30, // Seconds

      // Kill Franz for consuming too much memory
      "memory_limit": 2000000, // Bytes
      "memory_limit_interval": 5, // Seconds

      // Logger settings: https://github.com/sczizzo/slog
      "slog": {
        "timestamp_field": "timestamp",
        "timestamp_format": "%Y-%m-%dT%H:%M:%S.%L%z",
        "message_field": "event",
        "shift_age": 7,
        "shift_size": 1048576
      },

      // All input configs are files by convention
      "input": {
        "configs": [

          // Only "type" and "includes" are required
          {
            "type": "example",                          // A nice name
            "includes": [ "/path/to/your.*.log" ],      // File path globs
            "excludes": [ "your.bad.*.log" ],           // Basename globs
            "multiline": "(?i-mx:^[a-z]{3} +\\d{1,2})", // Stringified RegExp
            "drop": "(?i-mx:^\\d)",                     // Same story.
            "json?": false                              // JSON-formatted?
          }
        ],

        // Advanced configuration (optional)
        "discover_interval": 60, // Period to check for new files
        "discover_bound": 25000, // Limit discovery queue size
        "watch_interval": 2,     // Period to watch for file changes
        "watch_bound": 15000,    // Limit watch queue size
        "flush_interval": 45,    // Period to flush multiline events
        "block_size": 102400,    // Block size for tail reads
        "read_limit": 512000,    // Maximum size for a read
        "line_limit": 512000,    // Maximum size for a line
        "buffer_limit": 300,     // Maximum lines for multiline
        "tail_bound": 15000,     // Limit tail queue size
        "play_catchup?": true    // Pick up where we left off
      },


      // If you provide both RabbitMQ and Kafka configurations, Franz will
      // prefer RabbitMQ. If you provide neither, events are printed to STDOUT
      "output": {

        // RabbitMQ
        "rabbitmq": {

          // Must be a consistently-hashed exchange!
          "exchange": {
            "name": "logs"
          },

          // See Bunny docs for connection configuration:
          // http://rubybunny.info/articles/connecting.html
          // http://rubybunny.info/articles/tls.html
          "connection": {
            "port": 5672,
            "host": "localhost",
            "vhost": "/logs",
            "user": "logs",
            "pass": "logs"

            // Sample TLS (SSL) attributes:
            // "port": 5671,
            // "tls": true,
            // "tls_cert": "/path/to/client.cert",
            // "tls_key": "/path/to/client.key",
            // "tls_ca_certificates": [ "/path/to/cacert.pem" ],
            // "verify_peer": true
          }
        },

        // Kafka (experimental)
        "kafka": {
          "client_id": "hostname",
          "cluster": [ "localhost:9092" ],
          "type": "sync",
          "compression_codec": "snappy"
          "metadata_refresh_interval_ms": 600000,
          "max_send_retries": 3,
          "retry_backoff_ms": 100,
          "required_acks": 0,
          "ack_timeout_ms": 1500,
          "socket_timeout_ms": 10000
        },

        // HTTP (experimental)
        "http": {
          "server": "http://localhost:3000",
          "flush_interval": 5,
          "flush_size": 500
        },

        // Device (STDOUT implied if neither Kafka nor RabbitMQ configured)
        "device": "/dev/stdout",

        // Advanced configuration (optional)
        "stats_interval": 60, // Emit statistics periodically
        "bound": 25000,       // Limit output queue size
        "tags": [ "franz" ]   // Add a tag field to events
      }
    }

### Operation

At Blue Jeans, we deploy Franz with Upstart. Here's a minimal config:

    #!upstart
    description "franz"

    console log

    start on startup
    stop on shutdown
    respawn

    exec franz --config /path/to/franz.json

We actually use the [`bjn_franz` cookbook](https://github.com/sczizzo/bjn-franz-cookbook)
for Chef.

### Changelog

### v2.2

- Updated dependencies, improved packaging
- No more `TRACE`-level logging (demoted to `DEBUG`)
- Better command-line options backed by environment variables


#### v2.1

- Self-contained packages for OS X and Linux thanks to [Traveling Ruby](http://phusion.github.io/traveling-ruby) and [FPM](https://github.com/jordansissel/fpm)
- Dockerization using self-contained Linux package [available on the Docker Hub](https://registry.hub.docker.com/u/sczizzo/franz)
- Running Franz without arguments now prints help text (i.e. `--config` is now required)
- Don't watch files from previous executions unless there's a relevant configuration
- Rename `StdOut` to `Device`, no longer experimental
- Allow single state file if no glob is used
- Add autoreconnect logic to `Kafka` output
- Capture errors when parsing structured logs
- Add `FNM_EXTGLOB` flag for better glob matching
- Handle `EACCESS` on `IO.read` gracefully
- New `HTTP` output (experimental)
- Support for SSL with `HTTP` output (experimental)
- Allow for `nil` or `false` multiline configs
- Implement missing (yet documented) "tags" feature
- Remove default line limit
- Allow minimal configs

#### v2.0

- Added new outputs: `StdOut`, `Kafka` (experimental)

#### v1

Intial implementation of the file-to-RabbitMQ pipeline