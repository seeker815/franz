open_file_limit = `ulimit -n`.strip.to_i - 256
OPEN_FILE_LIMIT = open_file_limit <= 0 ? 256 : open_file_limit

require_relative 'franz/agg'
require_relative 'franz/config'
require_relative 'franz/discover'
require_relative 'franz/input'
require_relative 'franz/logger'
require_relative 'franz/metadata'
require_relative 'franz/output'
require_relative 'franz/tail'
require_relative 'franz/watch'