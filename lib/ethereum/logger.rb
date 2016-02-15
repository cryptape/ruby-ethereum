require 'logging'

module Ethereum
  module Logger

    DEFAULT_LOGLEVEL = :info

    class <<self
      def get(name='root')
        loggers[name] ||= create_logger(name)
      end

      def create_logger(name)
        logger = Logging.logger[name]
        logger.add_appenders Logging.appenders.stdout
        logger.level = DEFAULT_LOGLEVEL
      end

      def loggers
        @loggers ||= {}
      end
    end

  end
end
