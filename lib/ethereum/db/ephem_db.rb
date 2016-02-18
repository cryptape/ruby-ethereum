module Ethereum
  module DB
    class EphemDB < BaseDB

      def initialize
        @db = {}
        @kv = @db
      end

      def get(k)
        @db[k]
      end

      def put(k, v)
        @db[k] = v
      end

      def commit
        # do nothing
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
