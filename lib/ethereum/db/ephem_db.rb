# -*- encoding : ascii-8bit -*-

module Ethereum
  module DB
    class EphemDB < BaseDB

      def initialize
        @db = {}
      end

      def get(k)
        if has_key?
          @db[k]
        else
          raise KeyError, k.inspect
        end
      end

      def put(k, v)
        @db[k] = v
      end

      def delete(k)
        @db.delete(k)
      end

      def commit
        # do nothing
      end

      def has_key?(k)
        @db.has_key?(k)
      end
      alias :include? :has_key?

      def ==(other)
        other.instance_of?(self.class) && db == other.db
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

      def put_temporarily(k, v)
        inc_refcount(k, v)
        dec_refcount(k)
      end

    end
  end
end
