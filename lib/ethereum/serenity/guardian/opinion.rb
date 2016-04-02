# -*- encoding : ascii-8bit -*-

module Ethereum
  module Guardian

    ##
    # An object that stores the "current opinion" of a guardian, as computed
    # from their chain of bets
    #
    class Opinion

      attr :index, :seq, :prevhash, :blockhashes, :stateroots, :probs, :stateroot_probs, :induction_height, :withdrawal_height, :withdrawn

      attr_accessor :deposit_size

      def initialize(validation_code, index, prevhash, seq, induction_height)
        @validation_code = validation_code
        @index = index

        @blockhashes = []
        @stateroots = []
        @probs = []
        @stateroot_probs = []

        @prevhash = prevhash
        @seq = seq
        @induction_height = induction_height

        @withdrawal_height = 2**100
        @withdrawn = false
      end

      def process_bet(bet)
        if bet.seq != @seq
          Utils.debug "Bet sequence number does not match expectation: actual #{bet.seq} desired #{@seq}"
          return false
        end

        if bet.prevhash != @prevhash
          Utils.debug "Bet hash does not match prevhash: actual #{Utils.encode_hex(bet.prevhash)} desired #{Utils.encode_hex(@prevhash)} seq: #{bet.seq}"
          return false
        end

        raise AssertError, "Bet made after withdrawal! Slashing condition triggered!" if @withdrawn

        @seq = bet.seq + 1
        @prevhash = bet.full_hash

        # A bet with max height 2**256-1 signals withdrawal
        if bet.max_height == 2**256-1
          @withdrawn = true
          @withdrawal_height = @max_height
          Utils.debug "Guardian leaving!", index: bet.index
          return true
        end

        # Extend probs, blockhashes and state roots arrays as needed
        while @probs.size < bet.max_height
          @probs.push nil
          @blockhashes.push nil
          @stateroots.push nil
          @stateroot_probs.push nil
        end

        # Update probalities, blockhashes and stateroots
        bet.probs.size.times {|i| @probs[bet.max_height - i] = bet.probs[i] }
        bet.blockhashes.size.times {|i| @blockhashes[bet.max_height - i] = bet.blockhashes[i] }
        bet.stateroots.size.times {|i| @stateroots[bet.max_height - i] = bet.stateroots[i] }
        bet.stateroot_probs.size.times {|i| @stateroot_probs[bet.max_height - i] = bet.stateroot_probs[i] }

        true
      end

      def get_prob(h)
        @probs[h]
      end

      def get_blockhash(h)
        @bockhashes[h]
      end

      def get_stateroot(h)
        @stateroots[h]
      end

      def max_height
        @probs.size - 1
      end

    end

  end
end

