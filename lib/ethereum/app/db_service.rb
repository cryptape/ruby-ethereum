# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class DBService < DEVp2p::BaseService

      name 'db'
      default_config(
        db: {
          implementation: 'LevelDB'
        }
      )

      attr :db # implement DB::BaseDB interface

      def initialize(app)
        super(app)

        klass = ::Ethereum::DB.const_get(config[:db][:implementation])
        @db = klass.new File.join(app.config[:data_dir], 'leveldb')
      end

      def get(k)
        @db.get(k)
      end

      def put(k, v)
        @db.put(k, v)
      end

      def commit
        @db.commit
      end

      def delete(k)
        @db.delete(k)
      end

      def include?(k)
        @db.include?(k)
      end
      alias has_key? include?

      def inc_refcount(k, v)
        put(k, v)
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

      private

      def logger
        @logger ||= Ethereum::Logger.new 'db'
      end

    end

  end
end
