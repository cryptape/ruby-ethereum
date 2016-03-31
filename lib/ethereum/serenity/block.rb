# -*- encoding : ascii-8bit -*-

require 'forwardable'

module Ethereum
  ##
  # Note that the concept of extra data no longer exists. If a proposer wants
  # extra data they should just make the first transaction a dummy containing
  # that data.
  #
  class Block

    extend Forwardable
    def_delegators :header, :full_hash, :number, :number=, :sig, :sig=, :proposer, :proposer=, :txroot

    include RLP::Sedes::Serializable

    set_serializable_fields(
      header: BlockHeader,
      summaries: RLP::Sedes::CountableList.new(TransactionGroupSummary),
      transaction_groups: RLP::Sedes::CountableList.new(
        RLP::Sedes::CountableList.new(Transaction))
    )

    def initialize(header: nil, transactions: [], transaction_groups: nil, summaries: nil, number: nil, proposer: Address::ZERO, sig: BYTE_EMPTY)
      if transaction_groups && summaries && header
        prevright = 0
        summaries.zip(transaction_groups).each do |(s, g)|
          raise AssertError, "invalid transaction group hash" unless s.transaction_hash == Utils.keccak256_rlp(g)
          # Bounds must reflect a node in the binary tree (eg. 12-14 is valid,
          # 13-15 is not)
          raise AssertError, "invalid boundary" unless s.left_bound % (s.right_bound - s.left_bound) == 0
          raise AssertError, "summaries must be disjoint and in sorted order" unless prevright >= 0 && s.left_bound >= prevright && s.right_bound > s.left_bound && MAXSHARDS >= s.right_bound

          g.each do |tx|
            raise AssertError, "tx out of bounds" unless s.left_bound <= tx.left_bound && tx.left_bound < tx.right_bound && tx.right_bound <= s.right_bound
          end

          s.intrinsic_gas = g.map(&:intrinsic_gas).reduce(0, &:+)

          prevright = s.right_bound
        end

        raise AssertError, "reach gas limit" unless summaries.map(&:intrinsic_gas).reduce(0, &:+) < GASLIMIT
        raise AssertError, "header txroot mismatch" unless header.txroot == Utils.keccak256_rlp(summaries)
      else
        raise ArgumentError, "either give none or all of txgroups/summaries/header" if transaction_groups || summaries || header

        transactions.each do |tx|
          # TODO: should refactor into tx class
          raise ArgumentError, "tx boundary not align #{tx}" unless tx.left_bound % (tx.right_bound - tx.left_bound) == 0
          raise ArgumentError, "invalid bounds" unless tx.left_bound >= 0 && tx.right_bound > tx.left_bound && MAXSHARDS >= tx.right_bound
        end

        # TODO: Later, create a smarter algorithm for this
        # For now, we just create a big super-group with a global range
        # containing all of the desired transactions
        transaction_groups = [transactions]

        summary = TransactionGroupSummary.new(
          gas_limit: GASLIMIT,
          left_bound: 0,
          right_bound: MAXSHARDS,
          txgroup: transactions
        )
        summary.intrinsic_gas = transactions.map(&:intrinsic_gas).reduce(0, &:+)
        raise AssertError, "reach gas limit" unless summary.intrinsic_gas < GASLIMIT
        summaries = [summary]

        header = BlockHeader.new(
          number: number,
          txroot: Utils.keccak256_rlp(summaries),
          proposer: proposer,
          sig: sig
        )
      end

      super(header: header, summaries: summaries, transaction_groups: transaction_groups)
    end

    def add_transaction(tx, group_id=0)
      transaction_groups[group_id].push tx
      summaries[group_id].transaction_hash = Utils.keccak256_rlp transaction_groups[group_id]
      header.txroot = Utils.keccak256_rlp summaries
    end

  end
end
