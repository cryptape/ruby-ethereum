# -*- encoding : ascii-8bit -*-

module Ethereum
  module Guardian

    class DefaultBetStrategy

      include Constant
      include Config

      MAX_RECALC = 9
      MAX_LONG_RECALC = 14

      attr :id, :key, :addr

      attr_accessor :network

      def initialize(genesis_state, key,
                     clockwrong: false, bravery: 0.92, crazy_bet: false,
                     double_block_suicide: 2**200, double_bet_suicide: 2**200,
                     min_gas_price: 10**9)
        Utils.debug 'Initializing betting strategy'

        @db = genesis_state.db # bet strategy's database

        @id = Utils.mkid # id for network simulator
        @key = key # Guardian's private key
        @addr = ECDSAAccount.privtoaddr key

        # This counter is incremented every time a guardian joins;
        # it allows us to re-process the guardian set and refresh the guardians
        # that we have
        @guardian_signups = genesis_state.call_casper('getGuardianSignups', [])

        # A dict of opinion objects containing the current opinions of all
        # guardians
        @opinions = {}
        @bets = {} # A dict of lists of bets received from guardians
        @probs = [] # the probabilities that you are betting

        @finalized_hashes = [] # your finalized block hashes
        @stateroots = [] # your state roots
        @counters = [] # which counters have been processed

        # A hash containing the highest-sequence-number bet processed for each
        # guardian
        @highest_bet_processed = {}
        @time_received = {} # the time when you received an object

        # Hash lookup map; used mainly to check whether or not something has
        # already been received and processed
        @objects = {}

        # Blocks selected for each height
        @blocks = []

        # When you last explicitly requested to ask for a block; stored to
        # prevent excessively frequent lookups
        @last_asked_for_block = {}

        # When you last explicitly requested to ask for bets from a given
        # guardian; stored to prevent excessively frequent lookups
        @last_asked_for_bets = {}

        @txpool = {} # Pool of transactions worth including

        # Map of hash -> (tx, [(blknum, index), ...]) for transactions that are
        # in blocks that are not fully confirmed
        @finalized_txindex = {}

        # Counter for number of times a transaction entered an exceptional
        # condition
        @tx_exceptions = {}

        @last_bet_made = 0 # stored to prevent excessively frequent betting
        @last_time_sent_getblocks = 0 # stored to prevent frequent sent getblocks msg

        @index = -1 # your guardian index
        @former_index = nil

        @genesis_state_root = genesis_state.root
        @genesis_time = Utils.big_endian_to_int genesis_state.get_storage(GENESIS_TIME, WORD_ZERO)

        @last_block_produced = -1
        # next height at which you are eligible to produce (could be nil)
        @next_block_to_produce = -1

        @clockwrong = clockwrong
        @crazy_bet = crazy_bet # am I making crazy bets?
        @bravery = bravery # how quickly to converge toward finalization
        raise ArgumentError, "invalid bravery factor" unless bravery > 0 && bravery <= 1

        # What block number to create two blocks at, destroying my guardian slot
        # (for testing purposes; for non-byzantine nodes set to some really high
        # number)
        @double_block_suicide = double_block_suicide
        # What seq to create two bets at (also destructively, for testing)
        @double_bet_suicide = double_bet_suicide

        # Next submission delay (should be 0 on livenet; nonzero for testing)
        rand_submission_delay

        # List of proposers for blocks, calculated into the future just-in-time
        @proposers = []

        @prevhash = WORD_ZERO # for betting
        @seq = 0  # for betting

        @tracked_tx_hashes = []

        # If we only partially calculate state roots, store the index at which
        # to start calculating next time you make a bet
        @calc_state_roots_from = 0 

        @min_gas_price = min_gas_price # minimum gas price I accept

        # Create my guardian set
        update_guardian_set genesis_state
        Utils.debug "Found #{@opinions.size} guardians in genesis"

        # The height at which this guardian is added
        @induction_height = @index >= 0 ? genesis_state.call_casper('getGuardianInductionHeight', [@index]) : 2**100
        Utils.debug "Initialized guardian", address: Utils.encode_hex(@addr), index: @index, induction_height: @induction_height

        @withdrawn = false
        @max_finalized_height = -1 # max height which is finalized from your point of view
        @recently_discovered_blocks = []

        # When will I suicide?
        if @double_block_suicide < 2**40
          if @double_block_suicide < @next_block_to_produce
            Utils.debug "Suiciding at block #{@next_block_to_produce}"
          else
            Utils.debug "Suiciding at some block after #{@double_block_suicide}"
          end
        end
        Utils.debug "List of", proposers: @proposers

        # Am I byzantine?
        @byzantine = @crazy_bet || @double_block_suicide < 2**80 || @double_bet_suicide < 2**80
      end

      def add_transaction(tx, track: false)
        if !@objects.has_key?(tx.full_hash) || (@time_received.fetch(tx.full_hash, 0) < now - 15)
          Utils.debug "Received transaction", hash: Utils.encode_hex(tx.full_hash)[0,16]

          @objects[tx.full_hash] = tx
          @time_received[tx.full_hash] = now
          @txpool[tx.full_hash] = tx
          if track
            @tracked_tx_hashes.push tx.full_hash
          end

          nm = NetworkMessage.new :transaction, [RLP.encode(tx)]
          network.broadcast(self, RLP.encode(nm))
        end
      end

      def on_receive(objdata, sender_id)
        obj = Utils.rlp_decode objdata, sedes: NetworkMessage

        case obj.type
        when NetworkMessage::TYPES[:block]
          blk = Utils.rlp_decode obj.args[0], sedes: Block
          receive_block blk
        when NetworkMessage::TYPES[:bet]
          bet = Bet.deserialize obj.args[0]
          receive_bet bet
        when NetworkMessage::TYPES[:bet_request]
          index = Utils.big_endian_to_int obj.args[0]
          seq = Utils.big_endian_to_int obj.args[1]
          return unless @bets.has_key?(index)

          bets = (seq..@highest_bet_processed[index]).map {|x| @bets[index][x] }
          if bets.size > 0
            messages = bets.map do |b|
              RLP.encode NetworkMessage.new(:bet, [b.serialize])
            end
            network.direct_send self, sender_id, RLP.encode(NetworkMessage.new(:list, messages))
          end
        when NetworkMessage::TYPES[:transaction]
          tx = Utils.rlp_decode obj.args[0], sedes: Transaction
          add_transaction(tx) if should_include_transaction?(tx)
        when NetworkMessage::TYPES[:getblock]
          # Asking for block by number
          blk = nil
          if obj.args[0].size < 32
            blknum = Utils.big_endian_to_int obj.args[0]
            if blknum < @blocks.size && @blocks[blknum].true?
              blk = @blocks[blknum]
            end
          else
            o = @objects[obj.args[0]]
            blk = o if o.instance_of?(Block)
          end

          if blk
            msg = NetworkMessage.new :block, [RLP.encode(blk)]
            network.direct_send self, sender_id, RLP.encode(msg)
          end
        when NetworkMessage::TYPES[:getblocks]
          blknum = Utils.big_endian_to_int obj.args[0]
          messages = []

          (blknum...@blocks.size)[0,30].each do |h|
            if @blocks[h]
              messages.push RLP.encode(NetworkMessage.new(:block, [RLP.encode(@blocks[h])]))
            end
          end

          network.direct_send self, sender_id, RLP.encode(NetworkMessage.new(:list, messages))

          if blknum < @blocks.size && @blocks[blknum]
            network.direct_send self, sender_id, RLP.encode(NetworkMessage.new(:block, [RLP.encode(@blocks[blknum])]))
          end
        when NetworkMessage::TYPES[:list]
          obj.args.each do |x|
            on_receive x, sender_id
          end
        end
      end

      def receive_block(block)
        return if @objects.has_key?(block.full_hash) # already processed
        Utils.debug "Received block", number: block.number, hash: Utils.encode_hex(block.full_hash)[0,16], recipient: @index

        # Update the lengths of our main lists to make sure they can store the
        # data we will be calculating
        while @blocks.size <= block.number
          @blocks.push nil
          @stateroots.push nil
          @finalized_hashes.push nil
          @probs.push 0.5
        end

        # If we are not sufficiently synced, try to sync previous blocks first
        if block.number >= @calc_state_roots_from + ENTER_EXIT_DELAY - 1
          Utils.debug "Not sufficiently synced to receive this block (#{block.number})\n"

          if @last_time_sent_getblocks < now - 5
            Utils.debug "asking for blocks", index: @index
            network.broadcast self, RLP.encode(NetworkMessage.new(:getblocks, [Utils.encode_int(@max_finalized_height+1)]))
            @last_time_sent_getblocks = now
          end

          return
        end

        # If the block is invalid, return
        check_state = get_state_at_height block.number - ENTER_EXIT_DELAY + 1
        unless check_state.block_valid?(block)
          Utils.debug "ERR: Received invalid block: #{block.number} #{Utils.encode_hex(block.full_hash)[0,16]}"
          return
        end

        check_state2 = get_state_at_height [@max_finalized_height, @calc_state_roots_from-1].min
        vs = check_state2.call_casper 'getGuardianSignups', []
        if vs > @guardian_signups
          Utils.debug "updating guardian signups", shouldbe: vs, lastcached: @guardian_signups
          @guardian_signups = vs
          update_guardian_set check_state2
        end

        if @blocks[block.number].nil?
          @blocks[block.number] = block
        else
          Utils.debug "Caught a double block!"

          bytes1 = RLP.encode @blocks[block.number].header
          bytes2 = RLP.encode block.header

          new_tx = Transaction.new(CASPER, 500000+1000*bytes1.size+1000*bytes2.size, data: Casper.contract.encode('slashBlocks', [bytes1, bytes2]))
          add_transaction new_tx, track: true
        end

        # Store the block as having been received
        @objects[block.full_hash] = block
        @time_received[block.full_hash] = now
        @recently_discovered_blocks.push block.number
        time_delay = now - (@genesis_time + BLKTIME * block.number)
        Utils.debug "Received good block", height: block.number, hash: Utils.encode_hex(block.full_hash)[0,16], time_delay: time_delay

        # Add transactions to the unconfirmed transaction index
        block.transaction_groups.each_with_index do |g, i|
          g.each_with_index do |tx, j|
            unless @finalized_txindex.has_key?(tx.full_hash)
              unless @unconfirmed_txindex.has_key?(tx.full_hash)
                @unconfirmed_txindex[tx.full_hash] = [tx, []]
              end
              @unconfirmed_txindex[tx.full_hash][1].push [block.number, block.full_hash, i, j]
            end
          end
        end

        # Re-broadcast the block
        network.broadcast self, RLP.encode(NetworkMessage.new(:block, [RLP.encode(block)]))

        # Bet
        if (@index % VALIDATOR_ROUNDS) == (block.number % VALIDATOR_ROUNDS)
          Utils.debug "betting", index: @index, height: block.number
          mkbet
        end
      end

      def receive_bet(bet)
        # Do not process the bet if 1) we already processed it, or 2) it comes
        # from a guardian not in the current guardian set
        return if @objects.has_key?(bet.full_hash) || !@opinions.has_key?(bet.index)

        @objects[bet.full_hash] = bet
        @time_received[bet.full_hash] = now

        # Re-broadcast it
        network.broadcast(self, RLP.encode(NetworkMessage.new(:bet, [bet.serialize])))

        # Do we have a duplicate? If so, slash it
        if @bets[bet.index].has_key?(bet.seq)
          Utils.debug "Caught a double bet!"

          bytes1 = @bets[bet.index][bet.seq].serialize
          bytes2 = bet.serialize

          new_tx = Transaction.new(CASPER, 500000 + 1000*bytes1.size + 1000*bytes2.size,
                                   data: Casper.contract.encode('slashBets', [bytes1, bytes2]))

          add_transaction new_tx, track: true
        end

        @bets[bet.index][bet.seq] = bet

        # If we have an unbroken chain of bets from 0 to N, and last round we
        # had an unbroken chain only fron 0 to M, then process bets M+1..N.
        # For example, if we had bets 0, 1, 2, 4, 5, 7, now we receive 3, then
        # we assume bets 0, 1, 2 were already processed but now process 3, 4, 5
        # (but NOT 7)
        Utils.debug "receiving a bet", seq: bet.seq, index: bet.index, recipient: @index

        proc = 0
        while @bets[bet.index].include?((@highest_bet_processed[bet.index] + 1))
          result = @opinions[bet.index].process_bet(@bets[bet.index][@highest_bet_processed[@bet.index]+1])
          raise AssertError, 'failed to process bet' unless result.true?

          @highest_bet_processed[bet.index] += 1
          proc += 1
        end

        # Sanity check
        (@highest_bet_processed[bet.index]+1).times do |i|
          raise AssertError, "missing bet" unless @bets[bet.index].include?(i)
        end
        raise AssertError, 'seq mismatch' unless @opinions[bet.index].seq == @highest_bet_processed[bet.index]+1

        # If we did not process any bets after receiving a bet, that implies
        # that we are missing some bets. Ask for them.
        if proc == 0 && @last_asked_for_bets.fetch(bet.index, 0) < now + 10
          args = [bet.index, @highest_bet_processed[bet.index]+1].map {|i| Utils.encode_int(i) }
          msg = NetworkMessage.new :bet_request, args
          network.send_to_one self, RLP.encode(msg)
          @last_asked_for_bets[bet.index] = now
        end
      end

      def tick
        mytime = now

        # If 1) we should be making the blocks, and 2) the time has come to
        # produce a block, then produce a block
        if @index >= 0 && @next_block_to_produce
          target_time = @genesis_time + BLKTIME * @next_block_to_produce
          if mytime >= target_time + @next_submission_delay
            Utils.debug "making a block"
            recalc_state_roots
            make_block
            rand_submission_delay
          end
        elsif @next_block_to_produce.nil?
          add_proposers
        end

        if @last_bet_made < now - BLKTIME * VALIDATOR_ROUNDS * 1.5
          mkbet
        end
      end

      def now
        network.now
      end

      private

      # Compute as many state roots as possible
      def recalc_state_roots
        recalc_limit = @calc_state_roots_from > (@blocks.size - 20) ? MAX_RECALC : MAX_LONG_RECALC
        from = @calc_state_roots_from
        Utils.debug "recalculating", limit: recalc_limit, want: @blocks.size - from

        run_state = get_state_at_height from-1
        (from...@blocks.size)[0,recalc_limit].each do |h|
          prevblknum = Utils.big_endian_to_int run_state.get_storage(BLKNUMBER, WORD_ZERO)
          raise AssertError, "block number mismatch" unless h == prevblknum

          prob = @probs[h] || 0.5
          block = prob >= 0.5 ? @blocks[h] : nil
          run_state.block_state_transition block

          @stateroots[h] = run_state.root
          blknum = Utils.big_endian_to_int run_state.get_storage(BLKNUMBER, WORD_ZERO)
          raise AssertError, "block number mismatch" unless blknum == h + 1
        end

        ((from+recalc_limit)...@blocks.size).each do |h|
          @stateroots[h] = WORD_ZERO
        end

        @calc_state_roots_from = [from+recalc_limit, @blocks.size].min

        @calc_state_roots_from.times do |i|
          raise AssertError, "invalid state root" if [WORD_ZERO, nil].include?(@stateroots[i])
        end
      end

      def make_block
        gas = GASLIMIT
        txs = []

        # Try to include transactions in txpool
        @txpool.each do |h, tx|
          # If a transaction is not in the unconfirmed index and not in the
          # finalized index, then add it
          if !@unconfirmed_txindex.include?(h) && !@finalized_txindex.include?(h)
            Utils.debug "Adding transaction", hash: Utils.encode_hex(tx.full_hash)[0,16], blknum: @next_block_to_produce

            break if tx.gas > gas
            txs.push tx
            gas -= tx.gas
          end
        end

        # Publish most recent bets
        h = 0
        while h < @stateroots.size && ![nil, WORD_ZERO].include?(@stateroots[h])
          h += 1
        end

        latest_state_root = h > 0 ? @stateroots[h-1] : genesis_state_root
        raise AssertError, 'invalid state root' if [nil, WORD_ZERO].include?(latest_state_root)

        latest_state = State.new latest_state_root, @db

        Utils.debug "Producing block", number: @next_block_to_produce, known: @blocks.size, check_root_height: h-1

        @opinions.entries.shuffle.each do |i, o|
          latest_bet = latest_state.call_casper 'getGuardianSeq', [i]
          bet_height = latest_bet

          while @bets[i].include?(bet_height)
            Utils.debug "inserting bet", seq: latest_bet, index: i

            bet = @bets[i][bet_height]
            new_tx = Transaction.new CASPER, 200000 + 6600*bet.probs.size + 10000*(bet.blockhashes.size + bet.stateroots.size), data: bet.serialize

            if bet.max_height == 2**256-1
              @tracked_tx_hashes.push new_tx.full_hash
            end

            break if new_tx.gas > gas

            txs.push new_tx
            gas -= new_tx.gas
            bet_height += 1
          end

          if o.seq < latest_bet
            msg = NetworkMessage.new :bet_request, [i, o.seq+1].map{|i| Utils.encode_int(i) }
            network.send_to_one self, RLP.encode(msg)
            @last_asked_for_bets[i] = now
          end
        end

        # Process the unconfirmed index for the transaction. Note that a
        # transaction could theoretically get included in the chain multiple
        # times even within the same block, though if the account used to
        # process the transaction is sane the transaction should fail all but
        # one time
        @unconfirmed_txindex.each do |h, (tx, positions)|
          i = 0
          while i < positions.size
            blknum, blkhash, groupindex, txindex = positions[i]

            if [nil, WORD_ZERO].include?(@stateroots[blknum])
              i += 1
              next
            end

            p = @probs[blknum] # probability of the block being included
            if p > 0.95 # try running it
              grp_shard = @blocks[blknum].summaries[groupindex].left_bound
              logdata = State.new(@stateroots[blknum], @db).get_storage Utils.shardify(LOG, grp_shard), txindex
              logresult = Utils.big_endian_to_int RLP.decode(RLP.descend(logdata, 0))

              # If the transaction passed and block is finalized
              if p > 0.9999 && logresult == 2
                Utils.debug "Transaction finalized", hash: Utils.encode_hex(tx.full_hash)[0,16], blknum: blknum, blkhash: Utils.encode_hex(blkhash)[0,16], grpindex: groupindex, txindex: txindex

                @txpool.delete(h)
                @finalized_txindex[h] = [tx, []] unless @finalized_txindex.include?(h)

                @finalized_txindex[h][1].push [blknum, blkhash, groupindex, txindex, RLP.decode(logdata)]
                positions.delete(i)
              elsif p > 0.95 && logresult == 1
                positions.delete i

                @tx_exceptions[h] = @tx_exceptions.fetch(h, 0) + 1
                Utils.debug "Transaction inclusion finalized but transaction failed for the #{@tx_exceptions[h]}th time", hash: Utils.encode_hex(tx.full_hash)[0,16]
                # 10 strikes and we're out
                @txpool.delete(h) if @tx_exceptions[h] >= 10

              elsif logresult == 0
                # If the transaction failed (eg. due to OOG from block
                # gaslimit), remove it from the unconfirmed index, but not the
                # txpool, so that we can try to add it again
                Utils.debug "Transaction finalization attempt failed", hash: Utils.encode_hex(tx.full_hash)[0,16]
                positions.delete i
              else
                i += 1
              end
            elsif p < 0.05
              # If the block that the transaction was in didn't pass through,
              # remove it from the unconfirmed index, but not the txpool, so
              # that we can try to add it again
              Utils.debug "Transaction finalization attempt failed", hash: Utils.encode_hex(tx.full_hash)[0,16]
              positions.delete i
            else
              # Otherwise keep the transaction in the unconfirmed index
              i += 1
            end
          end

          @unconfirmed_txindex.delete(h) if positions.empty?
        end

        # Produce the block
        b = ECDSAAccount.sign_block Block.new(transactions: txs, number: @next_block_to_produce, proposer: @addr), @key
        network.broadcast self, RLP.encode(NetworkMessage.new(:block, [RLP.encode(b)]))
        receive_block b

        # If byzantine, produce two blocks
        if b.number >= @double_block_suicide
          Utils.debug "## Being evil and making two blocks!!!!!!!!\n"

          new_tx = ECDSAAccount.mk_transaction 1, 1, 1000000, "\x33"*ADDR_BYTES, 1, '', @key, create: true
          txs2 = txs + [new_tx]
          b2 = ECDSAAccount.sign_block Block.new(transactions: txs2, number: @next_block_to_produce, proposer: @addr), @key
          network.broadcast self, RLP.encode(NetworkMessage.new(:block, [RLP.encode(b2)]))
        end

        # Extend the list of block proposers
        @last_block_produced = @next_block_to_produce
        add_proposers

        # Log it
        td = now - (genesis_time + BLKTIME * b.number)
        Utils.debug "Making block", my_index: @index, number: b.number, hash: Utils.encode_hex(b.full_hash)[0,16], time_delay: td

        b
      end

      def rand_submission_delay
        @next_submission_delay = @clockwrong ? ((-BLKTIME*2)...(BLKTIME*6)).to_a.sample : 0
      end

      def mkbet
        return if now < @last_bet_made + 2
        @last_bet_made = now

        sign_from = [0, @max_finalized_height].max
        Utils.debug "Making probs", from: sign_from, to: @blocks.size-1

        srp = [] # state root probs
        srp_accum = finality_high

        # Bet on each height independently using our betting strategy
        (sign_from...@blocks.size).each do |h|
          prob, new_block_hash, ask = bet_at_height(
            @opinions,
            h,
            @blocks[h].true? ? [@blocks[h]] : [],
            @time_received,
            @genesis_time,
            now
          )

          # Do we need to ask for a block from the network?
          if ask && !@last_asked_for_block.has_key?(new_block_hash) && (@last_asked_for_block[new_block_hash] < now + 12)
            Utils.debug "Suspiciously missing a block, asking for it explicitly.", number: h, hash: Utils.encode_hex(new_block_hash)[0,16]
            network.broadcast self, RLP.encode(NetworkMessage.new(:getblock, [new_block_hash]))
            @last_asked_for_block[new_block_hash] = now
          end

          # Dig our preferred block hash change?
          if @blocks[h].true? && new_block_hash != @blocks[h].full_hash
            unless [nil, WORD_ZERO].include?(new_block_hash)
              Utils.debug "Changing block selection", height: h,
                pre: Utils.encode_hex(@blocks[h].full_hash[0,8]),
                post: Utils.encode_hex(new_block_hash[0,8])
              raise AssertError, "block number mismatch" unless @objects[new_block_hash].number == h
              @blocks[h] = @objects[new_block_hash]
              @recently_discovered_blocks.push h
            end
          end

          # If the probability of a block flips to the other side of 0.5, that
          # means that we should recalculate the state root at least from that
          # point (and possibly earlier)
          if ((prob - 0.5) * (@probs[h] - 0.5) <= 0  || (@probs[h] >= 0.5 && @recently_discovered_blocks.has_key?(h))) && h < @calc_state_roots_from
            Utils.debug "Rewinding", num_blocks: @calc_state_roots_from-h
            @calc_state_roots_from = h
          end

          @probs[h] = prob

          # Compute the state root probabilities
          if srp_accum == finality_high && prob >= finality_high
            srp.push finality_high
          else
            srp_accum *= prob
            srp.push [srp_accum, finality_low].max
          end

          # Finalized!
          if prob < finality_low || prob > finality_high
            Utils.debug 'Finalizing', height: h, my_index: @index
            @finalized_hashes[h] = prob > finality_high ? @blocks[h].full_hash : WORD_ZERO

            while h == @max_finalized_height+1
              @max_finalized_height = h
              Utils.debug "increasing max finalized height", new_height: h
              if h%10 != 0
                @opinions..keys.each do |i|
                  @opinions[i].deposit_size = get_optimistic_state.call_casper 'getGuardianDeposit', [i]
                end
              end
            end
          end
        end

        rootstart = [@calc_state_roots_from, @induction_height].max
        recalc_state_roots

        raise AssertError, "must be equal" unless @probs.size == @blocks.size
        raise AssertError, "must be equal" unless @stateroots.size == @blocks.size

        # If we are supposed to actually make a bet ... (if not, all the code
        # above is simply for personal information, ie. for a listening node to
        # determin its opinion on what the correct chain is)
        if @index >= 0 && @blocks.size > @induction_height && !@withdrawn && !@recently_discovered_blocks.empty?
          # Create and sign the bet
          blockstart = [@recently_discovered_blocks.keys.min, @induction_height].max
          probstart = [[sign_from, @induction_height].max, blockstart, rootstart].min
          srprobstart = [sign_from, @induction_height].max - sign_from

          raise AssertError, "not enough probs" unless srp.safe_slice(srprobstart..-1).size <= @probs.safe_slice(probstart..-1).size
          raise AssertError, "invalid probstart" unless srprobstart+sign_from >= probstart

          bet = Bet.new(
            @index, @blocks.size-1,
            @probs[probstart..-1].reverse,
            @blocks[blockstart..-1].reverse.map {|x| x.true? ? x.full_hash : WORD_ZERO },
            @stateroots[rootstart..-1].reverse,
            srp.each_with_index.map {|x, i| @stateroots[i] != WORD_ZERO ? x : finality_low }[srprobstart..-1].reverse,
            @prevhash,
            @seq,
            BYTE_EMPTY
          )
          o = sign_bet bet, @key

          @recently_discovered_blocks = []
          @prevhash = o.full_hash
          @seq += 1

          payload = RLP.encode NetworkMessage.new(:bet, [o.serialize])
          network.broadcast self, payload

          receive_bet o # process it myself

          # create two bets of the same seq (for testing)
          if @seq > @double_bet_suicide && !o.probs.empty?
            Utils.debug "wahhhhhh DOUBLE BETTING!!!!!!!!!!!!"
            o.probs[0] *= 0.9
            o = sign_bet o, @key
            payload = RLP.encode NetworkMessage.new(:bet, [o.serialize])
            network.broadcast self, payload
          end
        end
      end

      def should_include_transaction?(tx)
        check_state = get_optimistic_state

        hash = Utils.encode_hex(tx.full_hash)[0,16]
        o = check_state.tx_state_transition tx, override_gas: 250000+tx.intrinsic_gas, breaking: true
        if o.false?
          Utils.debug "No output from running transaction", hash: hash
          return false
        end

        output = Utils.int_array_to_bytes o
        # make sure that the account code matches
        account_code = check_state.get_code(tx.addr).sub(%r!#{"\x00"}+\z!)
        if account_code != ECDSAAccount.mandatory_account_code
          Utils.debug "Account code mismatch", hash: hash, shouldbe: ECDSAAccount.mandatory_account_code, reallyis: account_code
          return false
        end

        # make sure that the right gas price is in memory (and implicitly that
        # the tx succeeded)
        if output.size < 32
          Utils.debug "Min gas price not found in output, not including transaction", hash: hash
          return false
        end

        # make sure that the gas price is sufficient
        gas_price = Utils.big_endian_to_int(output[0,32])
        if gas_price < @min_gas_price
          Utils.debug "Gas price too low", shouldbe: @min_gas_price, reallyis: gas_price, hash: hash
          return false
        end

        Utils.debug "Transaction passes, should be included", hash: hash
        true
      end

      ##
      # Get a state object that we run functions or process blocks against
      #

      # finalized version (safer)
      def get_finalized_state
        get_state_at_height [@calc_state_roots_from - 1, @max_finalized_height].min
      end

      # optimistic version (more up-to-date)
      def get_optimistic_state
        get_state_at_height(@calc_state_roots_from - 1)
      end

      # Get a state object at a given height
      def get_state_at_height(h)
        root = h >= 0 ? @stateroots[h] : @genesis_state_root
        State.new root, @db
      end

      def update_guardian_set(check_state)
        check_state.call_casper('getNextGuardianIndex', []).times do |i|
          ctr = check_state.call_casper('getGuardianCounter', [i])
          if @counters[ctr].nil? # found new guardian!
            @counters[ctr] = 1

            ih = check_state.call_casper 'getGuardianInductionHeight', [i]
            valaddr = check_state.call_casper 'getGuardianAddress', [i]
            valcode = check_state.call_casper 'getGuardianValidationCode', [i]

            @opinions[i] = Opinion.new valcode, i, WORD_ZERO, 0, ih
            @opinions[i].deposit_size = check_state.call_casper 'getGuardianDeposit', [i]
            Utils.debug "Guardian inducted", index: i, address: valaddr, my_index: @index

            @bets[i] = {}
            @highest_bet_processed[i] = -1

            if valaddr == Utils.encode_hex(@addr) # it's me!
              @index = i
              add_proposers
              @induction_height = ih
              Utils.debug "I have been inducted!", index: @index
            end
          end
        end

        Utils.debug "Tracking #{@opinions.size} opinions"
      end

      def add_proposers
        h = @finalized_hashes.size - 1
        while h >= 0 && [nil, WORD_ZERO].include?(@stateroots[h])
          h -= 1
        end

        hs = h >= 0 ? @stateroots[h] : @genesis_state_root
        state = State.new hs, @db

        maxh = h + ENTER_EXIT_DELAY - 1
        (@proposers.size...maxh).each do |h|
          @proposers.push Casper.get_guardian_index(state, h)
          if @proposers.last == @index
            @next_block_to_produce = h
            return
          end
        end

        @next_block_to_produce = nil
      end

      def finality_low
        @finality_low ||= Guardian.decode_prob("\x00")
      end

      def finality_high
        @finality_high ||= Guardian.decode_prob("\xff")
      end

    end

  end
end
