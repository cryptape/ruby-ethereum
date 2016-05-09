# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class ChainService < DEVp2p::WiredService
      name 'chain'

      default_config(
        eth: {
          network_id: 0,
          genesis: '',
          pruning: -1
        },
        block: Ethereum::Env::DEFAULT_CONFIG
      )

      MAX_NEWBLOCK_PROCESSING_TIME_STATS = 1000

      def initialize(app)
        setup_db app.config

        super(app)

        logger.info 'initializing chain'
        coinbase = app.services.accounts.coinbase
        env = Ethereum::Env.new @db, config[:eth][:block]
        @chain = Chain.new env, new_head_cb: method(:on_new_head), coinbase: coinbase

        logger.info 'chain at', number: @chain.head.number
        if config[:eth][:genesis_hash]
          raise AssertError, "Genesis hash mismatch. Expected: #{config[:eth][:genesis_hash]}, Got: #{@chain.genesis.full_hash_hex}" unless config[:eth][:genesis_hash] == @chain.genesis.full_hash_hex
        end

        @synchronizer = App::Synchronizer.new(self, nil)

        @block_queue = SyncQueue.new # TODO: maxsize = block_queue_size
        @transaction_queue = SyncQueue.new # TODO: maxsize = transaction_queue_size
        @add_blocks_lock = false
        @add_transaction_lock = Semaphore.new # TODO

        @broadcast_filter = App::DuplicatesFilter.new
        @on_new_head_cbs = []
        @on_new_head_candidate_cbs = []
        @newblock_processing_times = []

        @processed_gas = 0
        @processed_elapsed = 0

        @wire_protocol = App::ETHProtocol
      end

      def syncing?
        @synchronizer.syncing?
      end

      def mining?
        app.services.include?('pow') && app.services.pow.active?
      end

      def add_transaction(tx, origin=nil, force_broadcast=false)
        if syncing?
          if force_broadcast
            raise AssertError, 'only allowed for local txs' if origin
            logger.debug 'force broadcasting unvalidated tx'
            broadcast_transaction tx, origin
          end

          return
        end

        logger.debug 'add_transaction', locked: !@add_transaction_lock.locked?, tx: tx
        raise ArgumentError, 'tx must be Transaction' unless tx.instance_of?(Transaction)
        raise ArgumentError, 'origin must be nil or DEVp2p::BaseProtocol' unless origin.nil? || origin.instance_of?(DEVp2p::BaseProtocol)

        if @broadcast_filter.include?(tx.full_hash)
          logger.debug 'discarding known tx'
          return
        end

        begin
          validate_transaction @chain.head_candidate, tx
          logger.debug 'valid tx, broadcasting'
          broadcast_transaction tx, origin
        rescue InvalidTransaction => e
          logger.debug 'invalid tx', error: e
          return
        end

        if origin # not locally added via jsonrpc
          if !mining? || syncing?
            logger.debug 'discarding tx', syncing: syncing?, mining: mining?
            return
          end
        end

        @add_transaction_lock.acquire
        success = @chain.add_transaction tx
        @add_transaction_lock.release

        on_new_head_candidate if success
        success
      end

      def add_block(t_block, proto)
        @block_queue.enq [t_block, proto] # blocks if full
        if !@add_blocks_lock
          @add_blocks_lock = true
          add_blocks
        end
      end

      def add_mined_block(block)
        logger.debug 'adding mined block', block: block
        raise ArgumentError, 'block must be Block' unless block.is_a?(Block)
        raise AssertError, 'invalid pow' unless block.header.check_pow

        if @chain.add_block(block)
          logger.debug 'added', block: block
          raise AssertError, 'block is not head' unless block == @chain.head
          broadcast_newblock block, block.chain_difficulty
        end
      end

      ##
      # if block is in chain or in queue
      #
      def knows_block(blockhash)
        return true if @chain.include?(blockhash)
        @block_queue.queue.any? {|(block, proto)| block.header.full_hash == blockhash }
      end

      def broadcast_newblock(block, chain_difficulty=nil, origin=nil)
        unless chain_difficulty
          raise AssertError, 'block not in chain' unless @chain.include?(block.full_hash)
          chain_difficulty = block.chain_difficulty
        end

        raise ArgumentError, 'block must be Block or TransientBlock' unless block.is_a?(Block) or block.instance_of?(App::TransientBlock)

        if @broadcast_filter.update(block.header.full_hash)
          logger.debug 'broadcasting newblock', origin: origin
          exclude_peers = origin ? [origin.peer] : []
          app.services.peermanager.broadcast(App::ETHProtocol, 'newblock', [block, chain_difficulty], {}, nil, exclude_peers)
        else
          logger.debug 'already broadcasted block'
        end
      end

      def broadcast_transaction(tx, origin=nil)
        raise ArgumentError, 'tx must be Transaction' unless tx.instance_of?(Transaction)

        if @broadcast_filter.update(tx.full_hash)
          logger.debug 'broadcasting tx', origin: origin
          exclude_peers = origin ? [origin.peer] : []
          app.services.peermanager.broadcast App::ETHProtocol, 'transactions', [tx], {}, nil, exclude_peers
        else
          logger.debug 'already broadcasted tx'
        end
      end

      def on_wire_protocol_start(proto)
        logger.debug 'on_wire_protocol_start', proto: proto
        raise AssertError, 'incompatible protocol' unless proto.instance_of?(@wire_protocol)

        # register callbacks
        %i(status newblockhashes transactions getblockhashes blockhashes getblocks blocks newblock getblockhashesfromnumber).each do |cmd|
          proto.send(:"receive_#{cmd}_callbacks").push method(:"on_receive_#{cmd}")
        end

        head = @chain.head
        proto.send_status head.chain_difficulty, head.full_hash, @chain.genesis.full_hash
      end

      def on_wire_protocol_stop(proto)
        raise AssertError, 'incompatible protocol' unless proto.instance_of?(@wire_protocol)
        logger.debug 'on_wire_protocol_stop', proto: proto
      end

      def on_receive_status(proto, eth_version, network_id, chain_difficulty, chain_head_hash, genesis_hash)
        logger.debug 'status received', proto: proto, eth_version: eth_version
        raise AssertError, 'eth version mismatch' unless eth_version == proto.version

        if network_id != config[:eth].fetch(:network_id, proto.network_id)
          logger.warn 'invalid network id', remote_network_id: network_id, expected_network_id: config[:eth].fetch(:network_id, proto.network_id)
          raise App::ETHProtocolError, 'wrong network id'
        end

        # check genesis
        if genesis_hash != @chain.genesis.full_hash
          logger.warn 'invalid genesis hash', remote_id: proto, genesis: Utils.encode_hex(genesis_hash)
          raise App::ETHProtocolError, 'wrong genesis block'
        end

        # request chain
        @synchronizer.receive_status proto, chain_head_hash, chain_difficulty

        # send transactions
        transactions = @chain.get_transactions
        unless transactions.empty?
          logger.debug 'sending transactions', remote_id: proto
          proto.send_transactions *transactions
        end
      end

      def on_receive_transactions(proto, transactions)
        logger.debug 'remote transactions received', count: transactions.size, remote_id: proto
        transactions.each do |tx|
          add_transaction tx, origin: proto
        end
      end

      def on_newblockhashes(proto, newblockhashes)
        logger.debug 'recv newblockhashes', num: newblockhashes.size, remote_id: proto
        raise AssertError, 'cannot handle more than 32 block hashes at one time' unless newblockhashes.size <= 32

        @synchronizer.receive_newblockhashes(proto, newblockhashes)
      end

      def on_receive_getblockhashes(proto, child_block_hash, count)
        logger.debug 'handle getblockhashes', count: count, block_hash: Utils.encode_hex(child_block_hash)

        max_hashes = [count, @wire_protocol::MAX_GETBLOCKHASHES_COUNT].min
        found = []

        unless @chain.include?(child_block_hash)
          logger.debug 'unknown block'
          proto.send_blockhashes
          return
        end

        last = child_block_hash
        while found.size < max_hashes
          begin
            last = RLP.decode_lazy(@chain.db.get(last))[0][0] # [head][prevhash]
          rescue KeyError
            # this can happen if we started a chain download, which did not complete
            # should not happen if the hash is part of the canonical chain
            logger.warn 'KeyError in getblockhashes', hash: last
            break
          end

          if last
            found.push(last)
          else
            break
          end
        end

        logger.debug 'sending: found block_hashes', count: found.size
        proto.send_blockhashes *found
      end

      def on_receive_blockhashes(proto, blockhashes)
        if blockhashes.empty?
          logger.debug 'recv 0 remote block hashes, signifying genesis block'
        else
          logger.debug 'on receive blockhashes', count: blockhashes.size, remote_id: proto, first: Utils.encode_hex(blockhashes.first), last: Utils.encode_hex(blockhashes.last)
        end

        @synchronizer.receive_blockhashes proto, blockhashes
      end

      def on_receive_getblocks(proto, blockhashes)
        logger.debug 'on receive getblocks', count: blockhashes.size

        found = []
        blockhashes[0, @wire_protocol::MAX_GETBLOCKS_COUNT].each do |bh|
          begin
            found.push @chain.db.get(bh)
          rescue KeyError
            logger.debug 'unknown block requested', block_hash: Utils.encode_hex(bh)
          end
        end

        unless found.empty?
          logger.debug 'found', count: found.dize
          proto.send_blocks *found
        end
      end

      def on_receive_blocks(proto, transient_blocks)
        blk_number = transient_blocks.empty? ? 0 : transient_blocks.map {|blk| blk.header.number }.max
        logger.debug 'recv blocks', count: transient_blocks.size, remote_id: proto, highest_number: blk_number

        unless transient_blocks.empty?
          @synchronizer.receive_blocks proto, transient_blocks
        end
      end

      def on_receive_newblock(proto, block, chain_difficulty)
        logger.debug 'recv newblock', block: block, remote_id: proto
        @synchronizer.receive_newblock proto, block, chain_difficulty
      end

      def on_receive_getblockhashesfromnumber(proto, number, count)
        logger.debug 'recv getblockhashesfromnumber', number: number, count: count, remote_id: proto

        found = []
        count = [count, @wire_protocol::MAX_GETBLOCKHASHES_COUNT].min

        for i in (number...(number+count))
          begin
            h = @chain.index.get_block_by_number(i)
            found.push h
          rescue KeyError
            logger.debug 'unknown block requested', number: number
          end
        end

        logger.debug 'sending: found block_hashes', count: found.size
        proto.send_blockhashes *found
      end

      private

      def logger
        @logger ||= Logger.new('eth.chainservice')
      end

      def on_new_head(block)
        logger.debug 'new head cbs', num: @on_new_head_cbs.size
        @on_new_head_cbs.each {|cb| cb.call block }
        on_new_head_candidate # we implicitly have a new head_candidate
      end

      def on_new_head_candidate
        @on_new_head_candidate_cbs.each {|cb| cb.call @chain.head_candidate }
      end

      def add_blocks
        logger.debug 'add_blocks', qsize: @block_queue.size, add_tx_lock: @add_transaction_lock.locked?
        raise AssertError unless @add_blocks_lock
        @add_transaction_lock.acquire

        while !@block_queue.empty?
          t_block, proto = @block_queue.peek

          if @chain.include?(t_block.header.full_hash)
            logger.warn 'known block', block: t_block
            @block_queue.deq
            next
          end

          if !@chain.include?(t_block.header.prevhash)
            logger.warn 'missing parent', block: t_block, head: @chain.head
            @block_queue.deq
            next
          end

          # FIXME: this is also done in validation and in synchronizer for
          # new_blocks
          if !t_block.header.check_pow
            logger.warn 'invalid pow', block: t_block
            # TODO: ban node
            warn_invalid t_block, 'InvalidBlockNonce'
            @block_queue.deq
            next
          end

          block = nil
          begin # deserialize
            t = Time.now
            block = t_block.to_block @chain.env
            elapsed = Time.now - t
            logger.debug 'deserialized', elapsed: elapsed, gas_used: block.gas_used, gpsec: gpsec(block.gas_used, elapsed)
          rescue InvalidTransaction => e
            logger.warn 'invalid transaction', block: t_block, error: e
            errtype = case e
                      when InvalidNonce then 'InvalidNonce'
                      when InsufficientBalance then 'NotEnoughCash'
                      when InsufficientStartGas then 'OutOfGasBase'
                      else 'other_transaction_error'
                      end
            warn_invalid t_block, errtype
            @block_queue.deq
            next
          rescue ValidationError => e
            logger.warn 'verification failed', error: e
            warn_invalid t_block, 'other_block_error'
            @block_queue.deq
            next
          end

          # check canary
          score = 0
          CANARY_ADDRESSES.each do |address|
            if block.get_storage_data(address, 1) > 0
              score += 1
            end
          end
          if score >= 2
            logger.warn 'canary triggered'
            next
          end

          # all check passed
          logger.debug 'adding', block: block
          if @chain.add_block(block, mining?)
            now = Time.now.to_i
            logger.info 'added', block: block, txs: block.transaction_count, gas_used: block.gas_used
            if t_block.newblock_timestamp && t_block.newblock_timestamp > 0
              total = now - t_block.newblock_timestamp
              @newblock_processing_times.push total
              @newblock_processing_times.shift if @newblock_processing_times.size > MAX_NEWBLOCK_AGE

              avg = @newblock_processing_times.reduce(0.0, &:+) / @newblock_processing_times.size
              max = @newblock_processing_times.max
              min = @newblock_processing_times.min
              logger.info 'processing time', last: total, avg: avg, max: max, min: min
            end
          else
            logger.warn 'could not add', block: block
          end

          @block_queue.deq
          sleep 0.001
        end
      ensure
        @add_blocks_lock = false
        @add_transaction_lock.release
      end

      def gpsec(gas_spent=0, elapsed=0)
        if gas_spent != 0
          @processed_gas += gas_spent
          @processed_elapsed += elapsed
        end

        (@processed_gas / (0.001 + @processed_elapsed)).to_i
      end

      def warn_invalid(block, errortype='other')
        # TODO: send to badblocks.ethereum.org
      end

      def setup_db(config)
        eth_config = config[:eth] || {}

        if eth_config[:pruning].to_i >= 0
          @db = DB::RefcountDB.new app.services.db

          if @db.db.include?("I am not pruning")
            raise "The database in '#{config[:data_dir]}' was initialized as non-pruning. Can not enable pruning now."
          end

          @db.ttl = eth_config[:pruning].to_i
          @db.db.put "I am pruning", "1"
          @db.commit
        else
          @db = app.services.db

          if @db.include?("I am pruning")
            raise "The database in '#{config[:data_dir]}' was initialized as pruning. Can not disable pruning now."
          end

          @db.put "I am not pruning", "1"
          @db.commit
        end

        if @db.include?('network_id')
          db_network_id = @db.get 'network_id'

          if db_network_id != eth_config[:network_id].to_s
            raise "The database in '#{config[:data_dir]}' was initialized with network id #{db_network_id} and can not be used when connecting to network id #{eth_config[:network_id]}. Please choose a different data directory."
          end
        else
          @db.put 'network_id', eth_config[:network_id].to_s
          @db.commit
        end

        raise AssertError, 'failed to setup db' if @db.nil?
      end

    end

  end
end
