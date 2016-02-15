require 'logging'

module Ethereum
  module Logger

    DEFAULT_LOG_LEVEL = :info
    DEFAULT_LOG_PATTERN = "%.1l, [%d] %5l -- %c: %m\n".freeze

    Logging.logger.root.level = DEFAULT_LOG_LEVEL

    Logging.logger.root.appenders = Logging.appenders.stdout(
      layout: Logging.layouts.pattern.new(pattern: DEFAULT_LOG_PATTERN))

    class <<self
      def get(name=:root)
        name = name.to_sym
        if name == :root
          Logging.logger.root
        else
          Logging.logger[name]
        end
      end
    end

  end
end
