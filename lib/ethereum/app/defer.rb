# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class Defer

      def initialize
        @cond = Celluloid::Condition.new

        @resolved = false
        @cancelled = false

        @result = nil
        @error = nil
      end

      def finished?
        resolved? || cancelled?
      end

      def resolved?
        @resolved
      end

      def cancelled?
        @cancelled
      end

      def result(timeout=nil)
        loop do
          return @result if finished?
          @cond.wait(timeout)
        end
      end

      def resolve(result)
        @result = result
        @resolved = true

        @cond.signal
      end

      def cancel(error)
        @error = error
        @cancelled = true

        @cond.signal
      end

    end

  end
end
