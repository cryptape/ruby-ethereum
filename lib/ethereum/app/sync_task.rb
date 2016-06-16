# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    ##
    # Synchronizes the chain starting from a given blockhash. Blockchain hash
    # is fetched from a single peer (which led to the unknown blockhash).
    # Blocks are fetched from the best peers.
    #
    class SyncTask
      MAX_BLOCKS_PER_REQUEST = 32
      INITIAL_BLOCKHASHES_PER_REQUEST = 16
      MAX_BLOCKHASHES_PER_REQUEST = 512

      BLOCKS_REQUEST_TIMEOUT = 32
      BLOCKHASHES_REQUEST_TIMEOUT = 32

      attr :start_block_number, :end_block_number

      def initialize(synchronizer, proto, blockhash, chain_difficulty=0, originator_only=false)
        @synchronizer = synchronizer
        @chain = synchronizer.chain
        @chainservice = synchronizer.chainservice

        @originating_proto = proto
        @originator_only = originator_only

        @blockhash = blockhash
        @chain_difficulty = chain_difficulty

        @requests = {} # proto => [cond, result]
        @start_block_number = @chain.head.number
        @end_block_number = @start_block_number + 1 # minimum synctask

        @run = Thread.new { run }
      end

      def run
        logger.info 'spawning new synctask'

        fetch_hashchain
      rescue
        logger.error $!
        logger.error $!.backtrace[0,20].join("\n")
        task_exit false
      end

      def task_exit(success=false)
        if success
          logger.debug 'successfully synced'
        else
          logger.warn 'syncing failed'
        end

        @synchronizer.synctask_exited(success)
      end

      def protocols
        return [@originating_proto] if @originator_only
        @synchronizer.protocols
      end

      def fetch_hashchain
        logger.debug 'fetching hashchain'

        blockhashes_chain = [@blockhash] # youngest to oldest
        blockhash = @blockhash = blockhashes_chain.last
        raise AssertError if @chain.include?(blockhash)

        # get block hashes until we found a known one
        max_blockhashes_per_request = INITIAL_BLOCKHASHES_PER_REQUEST
        chain_head_number = @chain.head.number
        while !@chain.include?(blockhash)
          blockhashes_batch = []

          # proto with highest difficulty should be the proto we got the
          # newblock from
          protos = self.protocols
          if protos.nil? || protos.empty?
            logger.warn 'no protocols available'
            return task_exit(false)
          end

          protos.each do |proto|
            logger.debug "syncing with", proto: proto
            next if proto.stopped?

            raise AssertError if @requests.has_key?(proto)
            deferred = Concurrent::IVar.new
            @requests[proto] = deferred

            proto.async.send_getblockhashes blockhash, max_blockhashes_per_request
            begin
              blockhashes_batch = deferred.value(BLOCKHASHES_REQUEST_TIMEOUT)
            rescue Defer::TimedOut
              logger.warn 'syncing hashchain timed out'
              next
            ensure
              @requests.delete proto
            end

            if blockhashes_batch.empty?
              logger.warn 'empty getblockhashes result'
              next
            end

            unless blockhashes_batch.all? {|bh| bh.instance_of?(String) }
              logger.warn "get wrong data type", expected: 'String', received: blockhashes_batch.map(&:class).uniq
              next
            end

            break
          end

          if blockhashes_batch.empty?
            logger.warn 'syncing failed with all peers', num_protos: protos.size
            return task_exit(false)
          end

          if @chain.include?(blockhashes_batch.last)
            blockhashes_batch.each do |bh| # youngest to oldest
              blockhash = bh

              if @chain.include?(blockhash)
                logger.debug "found known blockhash", blockhash: Utils.encode_hex(blockhash), is_genesis: (blockhash == @chain.genesis.full_hash)
                break
              else
                blockhashes_chain.push(blockhash)
              end
            end
          else # no overlap
            blockhashes_chain.concat blockhashes_batch
            blockhash = blockhashes_batch.last
          end

          logger.debug "downloaded #{blockhashes_chain.size} block hashes, ending with #{Utils.encode_hex(blockhashes_chain.last)}"
          @end_block_number = chain_head_number + blockhashes_chain.size
          max_blockhashes_per_request = MAX_BLOCKHASHES_PER_REQUEST
        end

        @start_block_number = @chain.get(blockhash).number
        @end_block_number = @start_block_number + blockhashes_chain.size

        logger.debug 'computed missing numbers', start_number: @start_block_number, end_number: @end_block_number

        fetch_blocks blockhashes_chain
      end

      def fetch_blocks(blockhashes_chain)
        raise ArgumentError, 'no blockhashes' if blockhashes_chain.empty?
        logger.debug 'fetching blocks', num: blockhashes_chain.size

        blockhashes_chain.reverse! # oldest to youngest
        num_blocks = blockhashes_chain.size
        num_fetched = 0

        while !blockhashes_chain.empty?
          blockhashes_batch = blockhashes_chain[0, MAX_BLOCKS_PER_REQUEST]
          t_blocks = []

          protos = self.protocols
          if protos.empty?
            logger.warn 'no protocols available'
            return task_exit(false)
          end

          proto = nil
          reply_proto = nil
          protos.each do |_proto|
            proto = _proto

            next if proto.stopped?
            raise AssertError if @requests.has_key?(proto)

            logger.debug 'requesting blocks', num: blockhashes_batch.size
            deferred = Concurrent::IVar.new
            @requests[proto] = deferred

            proto.async.send_getblocks *blockhashes_batch
            begin
              t_blocks = deferred.value(BLOCKS_REQUEST_TIMEOUT)
            rescue Defer::TimedOut
              logger.warn 'getblocks timed out, trying next proto'
              next
            ensure
              @requests.delete proto
            end

            if t_blocks.empty?
              logger.warn 'empty getblocks reply, trying next proto'
              next
            elsif !t_blocks.all? {|b| b.instance_of?(App::TransientBlock) }
              logger.warn 'received unexpected data', data: t_blocks
              t_blocks = []
              next
            end

            unless t_blocks.map {|b| b.header.full_hash } == blockhashes_batch[0, t_blocks.size]
              logger.warn 'received wrong blocks, should ban peer'
              t_blocks = []
              next
            end

            reply_proto = proto
            break
          end

          # add received t_blocks
          num_fetched += t_blocks.size
          logger.debug "received blocks", num: t_blocks.size, num_fetched: num_fetched, total: num_blocks, missing: (num_blocks - num_fetched)

          if t_blocks.empty?
            logger.warn 'failed to fetch blocks', missing: blockhashes_chain.size
            return task_exit(false)
          end

          t = Time.now
          logger.debug 'adding blocks', qsize: @chainservice.block_queue.size
          t_blocks.each do |blk|
            b = blockhashes_chain.shift
            raise AssertError unless blk.header.full_hash == b
            raise AssertError if blockhashes_chain.include?(blk.header.full_hash)

            @chainservice.add_block blk, reply_proto # this blocks if the queue is full
          end
          logger.debug 'adding blocks done', took: (Time.now - t)
        end

        # done
        last_block = t_blocks.last
        raise AssertError, 'still missing blocks' unless blockhashes_chain.empty?
        raise AssertError, 'still missing blocks' unless last_block.header.full_hash == @blockhash
        logger.debug 'syncing finished'

        # at this time blocks are not in the chain yet, but in the add_block queue
        if @chain_difficulty >= @chain.head.chain_difficulty
          @chainservice.broadcast_newblock last_block, @chain_difficulty, proto
        end

        task_exit(true)
      rescue
        logger.error $!
        logger.error $!.backtrace[0,10].join("\n")
        task_exit(false)
      end

      def receive_blocks(proto, t_blocks)
        logger.debug 'blocks received', proto: proto, num: t_blocks.size
        unless @requests.has_key?(proto)
          logger.debug 'unexpected blocks'
          return
        end
        @requests[proto].set t_blocks
      end

      def receive_blockhashes(proto, blockhashes)
        logger.debug 'blockhashes received', proto: proto, num: blockhashes.size
        unless @requests.has_key?(proto)
          logger.debug 'unexpected blockhashes'
          return
        end
        @requests[proto].set blockhashes
      end

      private

      def logger
        @logger ||= Logger.new('eth.sync.task')
      end

    end

  end
end
