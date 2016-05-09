# -*- encoding : ascii-8bit -*-

module Ethereum
  module DB
    class RefcountDB < BaseDB

      DEATH_ROW_OFFSET = 2**62

      ZERO_ENCODED = Utils.encode_int(0)
      ONE_ENCODED = Utils.encode_int(1)

      attr_accessor :ttl

      def initialize(db)
        @db = db
        @journal = []
        @death_row = []
        @kv = @db.respond_to?(:kv) ? @db.kv : nil

        self.ttl = 500
      end

      ##
      # Increase the reference count associated with a key.
      #
      def inc_refcount(k, v)
        node_object = RLP.decode ref_get(k)
        refcount = Utils.decode_int node_object[0]

        @journal.push [node_object[0], k]
        refcount = 0 if refcount >= DEATH_ROW_OFFSET

        new_refcount = Utils.encode_int(refcount+1)
        ref_put k, RLP.encode([new_refcount, v])

        if Logger.trace?(logger.name)
          logger.trace "increasing #{Utils.encode_hex(k)}=#{v} to #{refcount+1}"
        end
      rescue
        ref_put k, RLP.encode([ONE_ENCODED, v])
        @journal.push [ZERO_ENCODED, k]

        if Logger.trace?(logger.name)
          logger.trace "increasing #{Utils.encode_hex(k)}=#{v} to 1"
        end
      end
      alias :put :inc_refcount

      ##
      # Decrease the reference count associated with a key.
      #
      def dec_refcount(k)
        node_object = RLP.decode ref_get(k)
        refcount = Utils.decode_int node_object[0]

        if Logger.trace?(logger.name)
          logger.trace "decreasing #{Utils.encode_hex(k)} to #{refcount-1}"
        end

        raise AssertError, "refcount must be greater than zero!" unless refcount > 0

        @journal.push [node_object[0], k]
        new_refcount = Utils.encode(refcount-1)
        ref_put k, RLP.encode([new_refcount, node_object[1]])

        @death_row.push k if new_refcount == ZERO_ENCODED
      end
      alias :delete :dec_refcount

      def get_refcount(k)
        o = Utils.decode_int RLP.decode(ref_get(k))[0]
        o >= DEATH_ROW_OFFSET ? 0 : o
      rescue
        0
      end

      def get(k)
        RLP.decode(ref_get(k))[1]
      end

      ##
      # Kill nodes that are eligible to be killed, and remove the associated
      # deathrow record. Also delete old journals.
      #
      def cleanup(epoch)
        rlp_nodes = @db.get("deathrow:#{epoch}") rescue RLP.encode([])
        death_row_nodes = RLP.decode rlp_nodes

        pruned = 0
        offset = DEATH_ROW_OFFSET + epoch

        death_row_nodes.each do |node_key|
          begin
            refcount, val = RLP.decode ref_get(node_key)
            if Utils.decode_int(refcount) == offset
              @db.delete ref_key(node_key)
              pruned += 1
            end
          rescue
            logger.debug "in cleanup: #{$!}"
          end
        end
        logger.debug "#{pruned} nodes successfully pruned"

        @db.delete "deathrow:#{epoch}" rescue nil
        @db.delete "journal:#{epoch - ttl}" rescue nil
      end

      ##
      # Commit changes to the journal and death row to the database.
      #
      def commit_refcount_changes(epoch)
        timeout_epoch = epoch + ttl
        death_row_nodes = RLP.decode(@db.get("deathrow:#{timeout_epoch}")) rescue []

        @death_row.each do |node_key|
          refcount, val = RLP.decode ref_get(node_key)
          if refcount == ZERO_ENCODED
            new_refcount = Utils.encode_int(DEATH_ROW_OFFSET + timeout_epoch)
            ref_put node_key, RLP.encode([new_refcount, val])
          end
        end

        unless @death_row.empty?
          logger.debug "#{@death_row.size} nodes marked for pruning during block #{timeout_epoch}"
        end

        death_row_nodes.concat @death_row
        @death_row = []
        @db.put "deathrow:#{timeout_epoch}", RLP.encode(death_row_nodes)

        journal = RLP.decode(@db.get("journal:#{epoch}")) rescue []
        journal.extend @journal
        @journal = []
        @db.put "journal:#{epoch}", RLP.encode(journal)
      end

      ##
      # Revert changes made during an epoch
      #
      def revert_refcount_changes(epoch)
        timeout_epoch = epoch + ttl

        @db.delete("deathrow:#{timeout_epoch}") rescue nil

        begin
          journal = RLP.decode @db.get("journal:#{epoch}")
          journal.reverse.each do |(new_refcount, key)|
            node_object = RLP.decode ref_get(key)
            ref_put key, RLP.encode([new_refcount, node_object[1]])
          end
        rescue
          # do nothing
        end
      end

      def has_key?(k)
        @db.has_key? ref_key(k)
      end
      alias :include? :has_key?

      def put_temporarily(k, v)
        inc_refcount k, v
        dec_refcount k
      end

      def commit
        @db.commit
      end

      def ref_get(k)
        @db.get ref_key(k)
      end

      def ref_put(k, v)
        @db.put ref_key(k), v
      end

      def ref_key(k)
        "r:#{k}"
      end

      private

      def logger
        @logger ||= Logger.new 'eth.db.refcount'
      end

    end
  end
end
