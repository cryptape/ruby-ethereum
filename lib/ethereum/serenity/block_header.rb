# -*- encoding : ascii-8bit -*-

module Ethereum
  class BlockHeader

    include RLP::Sedes::Serializable
    extend Sedes

    set_serializable_fields(
      number: big_endian_int,
      txroot: trie_root,
      proposer: address,
      sig: binary
    )

    #def initialize(number: 0, txroot: Trie::BLANK_ROOT, proposer: Address::ZERO, sig: Constant::BYTE_EMPTY)
    #end

    def full_hash
      Utils.keccak256_rlp self
    end

  end
end
