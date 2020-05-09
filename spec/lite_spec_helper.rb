COVERAGE_MIN = 90
CURRENT_PATH = File.expand_path(File.dirname(__FILE__))

SERVER_DISCOVERY_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/sdam/**/*.yml").sort
SDAM_MONITORING_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/sdam_monitoring/*.yml").sort
SERVER_SELECTION_RTT_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/server_selection_rtt/*.yml").sort
SERVER_SELECTION_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/server_selection/**/*.yml").sort
MAX_STALENESS_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/max_staleness/**/*.yml").sort
CRUD_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/crud/**/*.yml").sort
CRUD2_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/crud_v2/**/*.yml").sort
RETRYABLE_WRITES_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/retryable_writes/**/*.yml").sort
RETRYABLE_READS_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/retryable_reads/**/*.yml").sort
COMMAND_MONITORING_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/command_monitoring/**/*.yml").sort
CONNECTION_STRING_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/connection_string/*.yml").sort
URI_OPTIONS_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/uri_options/*.yml").sort
DNS_SEEDLIST_DISCOVERY_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/dns_seedlist_discovery/*.yml").sort
GRIDFS_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/gridfs/*.yml").sort
TRANSACTIONS_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/transactions/*.yml").sort
TRANSACTIONS_API_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/transactions_api/*.yml").sort
CHANGE_STREAMS_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/change_streams/*.yml").sort
CMAP_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/cmap/*.yml").sort
AUTH_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/auth/*.yml").sort
CLIENT_SIDE_ENCRYPTION_TESTS = Dir.glob("#{CURRENT_PATH}/spec_tests/data/client_side_encryption/*.yml").sort

if ENV['CI']
  autoload :Byebug, 'byebug'
else
  # Load debuggers before loading the driver code, so that breakpoints
  # can be placed in the driver code on file/class level.
  begin
    require 'byebug'
  rescue LoadError
    require 'ruby-debug'
  end
end

require 'mongo'
require 'pp'

if BSON::Environment.jruby?
  # Autoloading appears to not work in some environments without these
  # gem calls. May have to do with rubygems version?
  gem 'ice_nine'
  gem 'timecop'
end

autoload :Benchmark, 'benchmark'
autoload :IceNine, 'ice_nine'
autoload :Timecop, 'timecop'

if BSON::Environment.jruby?
  require 'concurrent-ruby'
  PossiblyConcurrentArray = Concurrent::Array
else
  PossiblyConcurrentArray = Array
end

require 'support/utils'
require 'support/spec_config'

Mongo::Logger.logger = Logger.new($stdout)
unless SpecConfig.instance.client_debug?
  Mongo::Logger.logger.level = Logger::INFO
end
Encoding.default_external = Encoding::UTF_8

require 'support/matchers'
require 'support/lite_constraints'
require 'support/event_subscriber'
require 'support/common_shortcuts'
require 'support/client_registry'
require 'support/client_registry_macros'
require 'support/crypt'
require 'support/json_ext_formatter'
require 'support/sdam_formatter_integration'
require 'support/background_thread_registry'

require 'runners/server_discovery_and_monitoring'
require 'runners/server_selection_rtt'
require 'runners/server_selection'
require 'runners/sdam_monitoring'
require 'runners/crud'
require 'runners/command_monitoring'
require 'runners/cmap'
require 'runners/connection_string'
require 'runners/connection_string'
require 'runners/gridfs'
require 'runners/transactions'
require 'runners/auth'

if SpecConfig.instance.mri?
  require 'timeout_interrupt'
else
  require 'timeout'
  TimeoutInterrupt = Timeout
end

RSpec.configure do |config|
  config.extend(CommonShortcuts::ClassMethods)
  config.include(CommonShortcuts::InstanceMethods)
  config.extend(LiteConstraints)
  config.include(ClientRegistryMacros)

  if SpecConfig.instance.ci?
    SdamFormatterIntegration.subscribe
    config.add_formatter(JsonExtFormatter, File.join(File.dirname(__FILE__), '../tmp/rspec.json'))

    config.around(:each) do |example|
      SdamFormatterIntegration.assign_log_entries(nil)
      begin
        example.run
      ensure
        SdamFormatterIntegration.assign_log_entries(example.id)
      end
    end
  end

  if SpecConfig.instance.ci?
    # Allow a max of 30 seconds per test.
    # Tests should take under 10 seconds ideally but it seems
    # we have some that run for more than 10 seconds in CI.
    config.around(:each) do |example|
      TimeoutInterrupt.timeout(45) do
        example.run
      end
    end
  end

  if SpecConfig.instance.ci?
    if defined?(Rfc)
      unless BSON::Environment.jruby?
        Rfc::Rif.output_object_space_stats = true
      end

      # Uncomment this line to log memory and CPU statistics during
      # test suite execution to diagnose issues potentially related to
      # system resource exhaustion.
      #Rfc::Rif.output_system_load = true
    end
  end

  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
    c.max_formatted_output_length = 10000
  end

  if config.respond_to?(:fuubar_output_pending_results=)
    config.fuubar_output_pending_results = false
  end
end

EventSubscriber.initialize

if SpecConfig.instance.active_support?
  require "active_support/time"
  require 'mongo/active_support'
end

if File.exist?('.env.private')
  require 'dotenv'
  Dotenv.load('.env.private')
end
