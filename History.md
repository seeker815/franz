# Franz

Hi there, your old pal Sean Clemmer here. Imma talk quite a lot, so we might as
well get acquainted. I work on the Operations team at Blue Jeans Network, an
enterprise videoconferencing provider based in Mountain View, CA. Our team
provides infrastructure, tools, and support to the Engineering team, including,
most importantly for our purposes, log storage and processing.


## A lil History

Before the latest rearchitecture, logs at Blue Jeans were basically `rsync`ed
from every host to a central log server. Once on the box, a few processes came
afterwards to compress the files and scan for meeting identifiers. Our reporting
tools queried the log server with a meeting ID, and it replied with a list of
files and their location.

Compression saved a lot of space, and the search index was fairly small, since
we only needed to store a map of meeting IDs to file paths. If you wanted to
search the text, you need to log into the log server itself and `grep`.

And all of that worked for everyone until a point. At a certain number of files,
`grep` just wasn't fast enough, and worse, it was stealing resources necessary
for processing logs. At a certain volume, we just couldn't scan the logs fast
enough. Our scripts were getting harder to maintain, and we were looking for
answers sooner rather than later.


### Exploring our options

We did a fair amount of research and fiddling before deciding anything. We
looked especially hard at the Elasticsearch-Logstash-Kibana (ELK) stack,
Graylog2, and rearchitecting our scripts as a distributed system. In the end,
we decided we weren't smart enough and there wasn't enough time to design our
own system from the ground up. We also found Graylog2 to be a bit immature and
lacking in features compared to the ELK stack.

In the end, we appreciated the ELK stack had a lot of community and corporate
support, it was easy to get started, and everything was fairly well-documented.
Elasticsearch in particular seemed like a well-architected and professional
software project. Logstash had an active development community, and the author
Jordan Sissel soon joined Elasticsearch, Inc. as an employee.

There was a lot of hype around ELK, and I thought we could make it work.


### Our requirements

If you'll recall, the old system was really geared to look up log files based
on a special meeting ID. Quick, but no real search.

To emulate this with Elasticsearch we might store the whole file in a document
along with the meeting ID, which would make queries straightforward. A more
common approach in the ELK community is to store individual lines of a log file
in Elasticsearch documents. I figured we could get the file back by asking the
Elasticsearch cluster for an aggregation of documents corresponding to a given
file path on a given host.

To prove it to I slapped a couple scripts together, although the initial
implementation actually used *facets* and not *aggregations*. If we could get
the file back, that was everything we needed; we got advanced query support with
Elasticsearch and visualization with Kibana for free. Logstash was making it
easy for me to play around. Fun, even.


### Moving forward with ELK

I got to reading about the pipelines, and I realized pretty quick we were't
just gonna be able to hook Logstash right into Elasticsearch. You should put
a kind of buffer inbetween, and both RabbitMQ and Redis were popular at the
time. While I was developing our solution, alternative "forwarders" like
Lumberjack were just being introduced. After evaluating our options, I decided
on RabbitMQ based on team experience and the native Logstash support.

So the initial pipeline looked like this:

    Logstash -> RabbitMQ -> Logstash -> Elasticsearch <- Kibana

The first Logstash stage picked up logs with the `file` input and shipped them
out with the `rabbitmq` output. These log *events* sat in RabbitMQ until a
second, dedicated Logstash agent came along to parse it and shove it into
Elasticsearch for long-term storage and search. I slapped Kibana on top to
provide our users a usable window into the cluster.

And it all *kinda* worked. It wasn't very fast, and outages were fairly common,
but the all pieces were on the board. Over a few weeks I tuned and expanded the
RabbitMQ and Elasticsearch clusters, but still we were missing chunks of files,
missing whole files, and Logstash would die regularly with all kinds of strange
issues. Encoding issues, buffer issues, timeout issues, heap size issues.


### Fighting with Logstash

Surely we weren't the only people running into issues with this very popular
piece of open source software? Logstash has a GitHub project, a JIRA account,
and an active mailing list. I scoured issues, source code, pull requests, and
e-mail archives. These seemed like huge bugs:

1. *Multiline:* Both the multiline codec and filter had their issues. The codec
   is generally preffered, but even still you might miss the last line of your
   file, because Logstash does not implement *multiline flush*. Logstash will
   buffer the last line of a file indefinitely, thinking you may come back and
   write to the log.
2. *File handling:* Because Logstash keeps files open indefinitely, it can soak
   up file handles after running a while. We had tens of thousands of log files
   on some hosts, and Logstash just wasn't having it.
3. *Reconstruction:* Despite my initial proofs, we were having a lot of trouble
   reconstructing log files from individual events. Lines were often missing,
   truncated, and shuffled.

The multiline issue was actually fixed by the community, so I forked Logstash,
applied some patches, and did a little hacking to get it working right.

Fixing the second issue required delving deep into the depths of Logstash, the
`file` input, and Jordan Sissel's FileWatch project. FileWatch provides most of
the implementation for the `file` input, but it was riddled with bugs. I forked
the project and went through a major refactor to simplify and sanitize the code.
Eventually I was able to make it so Logstash would relinquish a file handle
some short interval after reading the file had ceased.

The third issue was rather more difficult. Subtle bugs at play. Rather than
relying on the `@timestamp` field, which we found did not have enough
resolution, I added a new field called `@seq`, just a simple counter, which
enabled us to put the events back in order. Still we were missing chunks, and
some lines appeared to be interleaved. Just weird stuff.

After hacking Logstash half to death we decided the first stage of the pipeline
would have to change. We'd still use Logstash to move events from RabbitMQ into
Elasticsearch, but we couldn't trust it to collect files.


### And so Franz was born

I researched Logstash alternatives, but there weren't many at the time. Fluentd
looked promising, but early testing revealed the multiline facility wasn't quite
there yet. Lumberjack was just gaining some popularity, but it was still too
immature. In the end, I decided I had a pretty good handle on our requirements
and I would take a stab at implementing a solution.

It would be risky, but Logstash and the community just weren't moving fast
enough for our needs. Engineering was justly upset with our logging "solution",
and I was pretty frantic after weeks of hacking and debugging. How hard could
it really be to tail a file and send the lines out to a queue?

After a few prototypes and a couple false starts, we had our boy Franz.



## Design and Implementation

From 10,000 feet Franz and Logstash are pretty similar; you can imagine Franz is
basically a Logstash agent configured with a `file` input and `rabbitmq` output.
Franz accepts a single configuration file that tells the process which files to
tail, how to handle them, and where to send the output. Besides solving the
three issues we discussed earlier, Franz provides a kind of `json` codec and
`drop` filter (in Logstash parlance).

I decided early on to implement Franz in Ruby, like Logstash. Unlike Logstash,
which is typically executed by JRuby, I decided to stick with Mat'z Ruby for
Franz in order to obtain a lower resource footprint at the expense of true
concurrency (MRI has a GIL).

Implementation-wise, Franz bears little resemblance to Logstash. Logstash has
a clever system which "compiles" the inputs, filters, and outputs into a single
block of code. Franz is a fairly straightward Ruby program with only a handful
of classes and a simple execution path.


### The Twelve-Factor App

I was heavily influenced by [the Twelve-Factor App](http://12factor.net):

1. *Codebase:* Franz is contained in a single repo on [GitHub](https://github.com/sczizzo/franz).
2. *Dependencies:* Franz provides a `Gemfile` to isolate dependencies.
3. *Config:* Franz separates code from configuration (no env vars, though).
4. *Backing Services:* Franz is agnostic to the connected RabbitMQ server.
5. *Build, release, run:* Franz is versioned and released as a [RubyGem](https://rubygems.org/gems/franz).
6. *Processes:* Franz provides mostly-stateless share-nothing executions.
7. *Port binding:* Franz isn't a Web service, so no worries here!
8. *Concurrency:* Franz is a single process and plays nice with Upstart.
9. *Disposability:* Franz uses a crash-only architecture, discussed below.
10. *Dev/prod parity:* We run the same configuration in every environment.
11. *Logs:* Franz provides structured logs which can be routed to file.
12. *Admin processes:* Franz is simple enough this isn't necessary.


### Crash-Only Architecture

Logstash assumes you might want to stop the process and restart it later, having
the new instance pick up where the last left off. To support this, Logstash (or
really, FileWatch) keeps a small "checkpoint" file, which is written whenever
Logstash is shut down.

Franz takes this one step further and implements a ["crash-only" design](http://lwn.net/Articles/191059).
The basic idea here the application does not distinguish between a crash and
a restart. In practical terms, Franz simply writes a checkpoint at regular
intervals; when asked to shut down, it aborts immediately.

Franz checkpoints are simple, too. It's just a `Hash` from log file paths to
the current `cursor` (byte offset) and `seq` (sequence number):

    {
      "/path/to/my.log": {
        "cursor": 1234,
        "seq": 99
      }
    }

The checkpoint file contains the `Marshal` representation of this `Hash`.


### Sash

The `Sash` is a data structure I discovered during the development of Franz,
which came out of the implementation of multiline flush. Here's a taste:

    s = Sash.new           # => #<Sash...>
    s.keys                 # => []
    s.insert :key, :value  # => :value
    s.get :key             # => [ :value ]
    s.insert :key, :crazy  # => :crazy
    s.mtime :key           # => 2014-02-18 21:24:30 -0800
    s.flush :key           # => [ :value, :crazy ]

For multilining, what you do is create a `Sash` keyed by each path, and insert
each line in the appropriate key as they come in from upstream. Before you
insert it, though, you check if the line in question matches the multiline
pattern for the key: If so, you flush the `Sash` key and write the result out as
an event. Now the `Sash` key will buffer the next event.

In fact, a `Sash` key will only ever contain lines for at most one event, and
the `mtime` method allows us to know how recently that key was modified. To
implement multiline flush correctly, we periodically check the `Sash` for old
keys and flush them according to configuration. `Sash` methods are threadsafe,
so we can do this on the side without interrupting the main thread.


### Slog

[Slog](https://github.com/sczizzo/slog) was also factored out of Franz, but
it's heavily inspired by Logstash. By default, output is pretty and colored (I
swear):

    Slog.new.info 'example'
    #
    #   {
    #     "level": "info",
    #     "@timestamp": "2014-12-25T06:22:43.459-08:00",
    #     "message": "example"
    #   }
    #

`Slog` works perfectly with Logstash or Franz when configured to treat the log
file as JSON; they'll add the other fields necessary for reconstruction.

More than anything, structured logging has changed how I approach logs. Instead
of writing *everything* to file, Franz strives to log useful events that contain
metadata. Instead of every request, an occasional digest. Instead of a paragraph
of text, a simple summary. Franz uses different log levels appropriately,
allowing end users to control verbosity.


### Execution Path

Franz is implemented as a series of stages connected via bounded queues:

    Input -> Discover -> Watch -> Tail -> Agg -> Output

Each of these stages is a class under the `Franz` namespace, and they run up
to a couple `Thread`s, typically a worker and maybe a helper (e.g. multiline
flush). Communicating via `SizedQueue`s helps ensure correctness and constrain
memory usage under high load.

0. `Input`: Actually wires together `Discover`, `Watch`, `Tail`, and `Agg`.
1. `Discover`: Performs half of file existence detection by expanding globs and
   keeping track of files known to Franz.
2. `Watch`: Works in tandem with `Discover` to maintain a list of known files and
   their status. Events are generated when a file is created, destroyed, or
   modified (including appended, truncated, and replaced).
3. `Tail`: Receives low-level file events from a `Watch` and handles the actual
   reading of files, providing a stream of lines.
4. `Agg`: Mostly aggregates `Tail` events by applying the multiline filter, but it
   also applies the `host` and `type` fields. Basically, it does all the post
   processing after we've retreived a line from a file.
5. `Output`: RabbitMQ output for Franz, based on the really-very-good [Bunny](https://github.com/ruby-amqp/bunny)
   client. You must declare an `x-consistent-hash` exchange, as we generate a
   random `Integer` for routing. Such is life.
