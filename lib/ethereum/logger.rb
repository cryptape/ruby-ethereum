# -*- encoding : ascii-8bit -*-

require 'logging'

module Ethereum
  class Logger

    DEFAULT_LOG_LEVEL = :info
    DEFAULT_LOG_PATTERN = "%.1l, [%d] %5l -- %c: %m\n".freeze

    Logging.logger.root.level = DEFAULT_LOG_LEVEL

    Logging.logger.root.appenders = Logging.appenders.stdout(
      layout: Logging.layouts.pattern.new(pattern: DEFAULT_LOG_PATTERN))

    class <<self
      def trace?(name)
        !!traces[name]
      end

      def set_trace(name, v=true)
        traces[name] = v
      end

      def traces
        @traces ||= {}
      end
    end

    attr :name

    def initialize(name, logger=nil)
      @name = name
      @logger = logger || Logging.logger[name]
    end

    def trace(msg, **kwargs)
      if Logger.trace?(name)
        @logger.info "TRACE #{msg}#{serialize_kwargs(kwargs)}"
      end
    end

    def fatal(msg, **kwargs)
      @logger.fatal "#{msg}#{serialize_kwargs(kwargs)}"
    end

    def error(msg, **kwargs)
      @logger.error "#{msg}#{serialize_kwargs(kwargs)}"
    end

    def warn(msg, **kwargs)
      @logger.warn "#{msg}#{serialize_kwargs(kwargs)}"
    end

    def info(msg, **kwargs)
      @logger.info "#{msg}#{serialize_kwargs(kwargs)}"
    end

    def debug(msg, **kwargs)
      @logger.debug "#{msg}#{serialize_kwargs(kwargs)}"
    end

    def serialize_kwargs(kwargs)
      " #{kwargs.map {|k,v| "#{k}=#{v}" }.join(' ')}"
    end

  end
end
