# -*- encoding : ascii-8bit -*-

module Ethereum
  class TransactionGroupSummary

    include RLP::Sedes::Serializable
    extend Sedes

    set_serializable_fields(
      gas_limit: big_endian_int,
      left_bound: big_endian_int,
      right_bound: big_endian_int,
      transaction_hash: binary
    )

    attr_accessor :intrinsic_gas

    def initialize(gas_limit: nil, left_bound: 0, right_bound: nil, txgroup: [], transaction_hash: nil)
      args = {
        gas_limit: gas_limit || Constant::GASLIMIT,
        left_bound: left_bound,
        right_bound: right_bound || (1 << (Constant::ADDR_BASE_BYTES*8)),
        transaction_hash: transaction_hash || Utils.keccak256_rlp(txgroup)
      }
      super(args)
    end

  end
end
