# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    ##
    # Handles the synchronization of blocks.
    #
    # There's only one sync task active at a time. In order to deal with the
    # worst case of initially syncing the wrong chain, a checkpoint blockhash
    # can be specified and synced via force_sync.
    #
    # Received blocks are given to chainservice.add_block, which has a fixed
    # size queue, the synchronization blocks if the queue is full.
    #
    # on_status:
    #   if peer.head.chain_difficulty > chain.head.chain_difficulty
    #     fetch peer.head and handle as newblock
    #
    # on_newblock:
    #   if block.parent
    #     add
    #   else
    #     sync
    #
    # on_blocks/on_blockhashes:
    #   if synctask
    #     handle to requester
    #   elsif unkonwn and has parent
    #     add to chain
    #   else
    #     drop
    #
    class Synchronizer

      MAX_NEWBLOCK_AGE = 5 # maximum age (in blocks) of blocks received as newblock

      attr :chain, :chainservice

      ##
      # @param force_sync [Array, NilClass] If passed in array, it must be in
      #   the form of tuple: (blockhash, chain_difficulty). Helper for long
      #   initial syncs to get on the right chain used with first
      #   status_received.
      #
      def initialize(chainservice, force_sync=nil)
        @chainservice = chainservice
        @force_sync = force_sync
        @chain = chainservice.chain
        @protocols = {} # proto => chain_difficulty
        @synctask = nil
      end

      def syncing?
        !!@synctask
      end

      def synctask_exited(success=false)
        @force_sync = nil if success
        @synctask = nil
      end

      def protocols
        @protocols = @protocols
          .map {|proto, diff| [proto, diff] }
          .select {|tuple| tuple[0].alive? && !tuple[0].stopped? }
          .to_h

        @protocols.keys.sort_by {|proto| -@protocols[proto] }
      end

      ##
      # Called if there's a newblock announced on the network.
      #
      def receive_newblock(proto, t_block, chain_difficulty)
        logger.debug 'newblock', proto: proto, block: t_block, chain_difficulty: chain_difficulty, client: proto.peer.remote_client_version

        if @chain.include?(t_block.header.full_hash)
          raise AssertError, 'chain difficulty mismatch' unless chain_difficulty == @chain.get(t_block.header.full_hash).chain_difficulty
        end

        @protocols[proto] = chain_difficulty

        if @chainservice.knows_block(t_block.header.full_hash)
          logger.debug 'known block'
          return
        end

        expected_difficulty = @chain.head.chain_difficulty + t_block.header.difficulty
        if chain_difficulty >= @chain.head.chain_difficulty
          # broadcast duplicates filtering is done in chainservice
          logger.debug 'sufficient difficulty, broadcasting', client: proto.peer.remote_client_version
          @chainservice.broadcast_newblock t_block, chain_difficulty, proto
        else
          age = @chain.head.number - t_block.header.number
          logger.debug "low difficulty", client: proto.peer.remote_client_version, chain_difficulty: chain_difficulty, expected_difficulty: expected_difficulty, block_age: age

          if age > MAX_NEWBLOCK_AGE
            logger.debug 'newblock is too old, not adding', block_age: age, max_age: MAX_NEWBLOCK_AGE
            return
          end
        end

        if @chainservice.knows_block(t_block.header.prevhash)
          logger.debug 'adding block'
          @chainservice.add_block t_block, proto
        else
          logger.debug 'missing parent'
          if @synctask
            logger.debug 'existing task, discarding'
          else
            @synctask = App::SyncTask.new self, proto, t_block.header.full_hash, chain_difficulty
          end
        end
      end

      ##
      # Called if a new peer is connected.
      #
      def receive_status(proto, blockhash, chain_difficulty)
        logger.debug 'status received', proto: proto, chain_difficulty: chain_difficulty

        @protocols[proto] = chain_difficulty

        if @chainservice.knows_block(blockhash) || @synctask
          logger.debug 'existing task or known hash, discarding'
          return
        end

        if @force_sync
          blockhash, difficulty = force_sync
          logger.debug 'starting forced synctask', blockhash: Utils.encode_hex(blockhash)
          @synctask = App::SyncTask.new self, proto, blockhash, difficulty
        elsif chain_difficulty > @chain.head.chain_difficulty
          logger.debug 'sufficient difficulty'
          @synctask = App::SyncTask.new self, proto, blockhash, chain_difficulty
        end
      end

      ##
      # No way to check if this really an interesting block at this point.
      # Might lead to an amplification attack, need to track this proto and
      # judge usefulness.
      #
      def receive_newblockhashes(proto, newblockhashes)
        logger.debug 'received newblockhashes', num: newblockhashes.size, proto: proto

        newblockhashes = newblockhashes.select {|h| !@chainservice.knows_block(h) }

        known = @protocols.include?(proto)
        if !known || newblockhashes.empty? || @synctask
          logger.debug 'discarding', known: known, synctask: syncing?, num: newblockhashes.size
          return
        end

        if newblockhashes.size != 1
          logger.warn 'supporting only one newblockhash', num: newblockhashes.size
        end
        blockhash = newblockhashes[0]

        logger.debug 'starting synctask for newblockhashes', blockhash: Utils.encode_hex(blockhash)
        @synctask = App::SyncTask.new self, proto, blockhash, 0, true
      end

      def receive_blocks(proto, t_blocks)
        logger.debug 'blocks received', proto: proto, num: t_blocks.size
        if @synctask
          @synctask.receive_blocks proto, t_blocks
        else
          logger.warn 'no synctask, not expecting blocks'
        end
      end

      def receive_blockhashes(proto, blockhashes)
        logger.debug 'blockhashes received', proto: proto, num: blockhashes.size
        if @synctask
          @synctask.receive_blockhashes proto, blockhashes
        else
          logger.warn 'no synctask, not expecting blockhashes'
        end
      end

      private

      def logger
        @logger ||= Logger.new('eth.sync')
      end
    end

  end
end
