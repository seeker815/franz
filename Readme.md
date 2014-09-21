# Franz

Franz ships line-oriented log files to [RabbitMQ](http://www.rabbitmq.com/).
Think barebones [logstash](http://logstash.net/) in pure Ruby with more modest
compute and memory requirements.

This is really to avoid the JVM tax, but you probably still want logstash agents
doing the bulk of the log processing. Using this setup, RabbitMQ and logstash
may be scaled and restarted independently, so new configurations may be applied
without interrupting those precious log hosts.

Even so, Franz was designed to be interruped. Before exiting, Franz drains his
event queues and write any "leftover" state disk. When he's called next, he picks
up those leftovers and continues as if he were paused.

He's also got a couple of improvements over logstash. Let's discuss!


## Improvements

First let me say logstash is an awesome hunk of software thanks to the hard
work of Jordan Sissel and the entire logstash community. Keep it up!

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
