# -*- encoding : ascii-8bit -*-

module Ethereum
  module DB
    ##
    # Used for making temporary objects.
    #
    class OverlayDB < BaseDB

      def initialize(db)
        @db = db
        @overlay = {}
      end

      def get(k)
        if @overlay.has_key?(k)
          raise KeyError, k.inspect if @overlay[k].nil?
          return @overlay[k]
        end

        db.get k
      end

      def put(k, v)
        @overlay[k] = v
      end

      def put_temporarily(k, v)
        inc_refcount k, v
        dec_refcount k
      end

      def delete(k)
        @overlay[k] = nil
      end

      def commit
        # do nothing
      end

      def has_key?(k)
        @overlay.has_key?(k) ? !@overlay[k].nil? : db.has_key?(k)
      end
      alias :include? :has_key?

      def ==(other)
        other.instance_of?(self.class) && db = other.db
      end

      def inc_refcount(k, v)
        put k, v
      end

      def dec_refcount(k)
        # do nothing
      end

      def revert_refcount_changes(epoch)
        # do nothing
      end

      def commit_refcount_changes(epoch)
        # do nothing
      end

      def cleanup(epoch)
        # do nothing
      end

    end
  end
end
