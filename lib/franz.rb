require_relative 'franz/agg'
require_relative 'franz/config'
require_relative 'franz/discover'
require_relative 'franz/input'
require_relative 'franz/logger'
require_relative 'franz/output'
require_relative 'franz/output/rabbitmq'
require_relative 'franz/queue'
require_relative 'franz/tail'
require_relative 'franz/watch'


# A file-to-RabbitMQ or file-to-Kafka shipper. Like a stripped-down, hyper-focused Logstash agent
module Franz ; end