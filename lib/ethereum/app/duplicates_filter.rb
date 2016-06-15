# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class DuplicatesFilter

      def initialize(max_items=128)
        @max_items = max_items
        @filter = []
      end

      def update(data)
        if @filter.include?(data)
          @filter.push @filter.shift
          false
        else
          @filter.push data
          @filter.shift if @filter.size > @max_items
          true
        end
      end

      def include?(v)
        @filter.include?(v)
      end

    end

  end
end
