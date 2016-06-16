# -*- encoding : ascii-8bit -*-

require 'leveldb'

module Ethereum
  module DB
    class LevelDB
      include BaseDB

      # FIXME: workaround, because leveldb gem doesn't allow put empty string
      EMPTY_STRING = Utils.keccak256('').freeze

      def initialize(dbfile)
        logger.info "opening LevelDB", path: dbfile

        @dbfile = dbfile
        reopen

        @commit_counter = 0
        @uncommited = {}
      end

      def reopen
        @db = ::LevelDB::DB.new @dbfile
      end

      def get(k)
        logger.trace 'getting entry', key: Utils.encode_hex(k)[0,8]

        if @uncommited.has_key?(k)
          raise KeyError, 'key not in db' unless @uncommited[k]
          logger.trace "from uncommited"
          return @uncommited[k]
        end

        logger.trace "from db"
        raise KeyError, k.inspect unless @db.exists?(k)
        v = @db.get(k)
        o = decompress v
        @uncommited[k] = o

        o
      end

      def put(k, v)
        logger.trace 'putting entry', key: Utils.encode_hex(k)[0,8], size: v.size
        @uncommited[k] = v
      end

      def commit
        logger.debug "committing", db: self

        @db.batch do |b|
          @uncommited.each do |k, v|
            if v
              b.put k, compress(v)
            else
              b.delete k
            end
          end
        end
        logger.debug 'committed', db: self, num: @uncommited.size
        @uncommited = {}
      end

      def delete(k)
        logger.trace 'deleting entry', key: key
        @uncommited[k] = nil
      end

      def has_key?(k)
        get(k)
        true
      rescue KeyError
        false
      end
      alias :include? :has_key?

      def ==(other)
        other.instance_of?(self.class) && db == other.db
      end

      def to_s
        "<DB at #{@db} uncommited=#{@uncommited.size}>"
      end
      alias inspect to_s

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

      private

      def logger
        @logger ||= Logger.new 'db.leveldb'
      end

      def decompress(x)
        x == EMPTY_STRING ? '' : x
      end

      def compress(x)
        x.empty? ? EMPTY_STRING : x
      end

    end
  end
end
