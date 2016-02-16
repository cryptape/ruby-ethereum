module Ethereum

##
  # A block header.
  #
  # If the block with this header exists as an instance of {Block}, the
  # connection can be made explicit by setting `BlockHeader.block`. Then,
  # `BlockHeader.state_root`, `BlockHeader.tx_list_root` and
  # `BlockHeader.receipts_root` always refer to the up-to-date value in the
  # block instance.
  #
  # * `@block` - an instance of {Block} or `nil`
  # * `@prevhash` - the 32 byte hash of the previous block
  # * `@uncles_hash` - the 32 byte hash of the RLP encoded list of uncle headers
  # * `@coinbase` - the 20 byte coinbase address
  # * `@state_root` - the root of the block's state trie
  # * `@tx_list_root` - the root of the block's transaction trie
  # * `@receipts_root` - the root of the block's receipts trie
  # * `@bloom` - bloom filter
  # * `@difficulty` - the block's difficulty
  # * `@number` - the number of ancestors of this block (0 for the genesis block)
  # * `@gas_limit` - the block's gas limit
  # * `@gas_used` - the total amount of gas used by all transactions in this block
  # * `@timestamp` - a UNIX timestamp
  # * `@extra_data` - up to 1024 bytes of additional data
  # * `@nonce` - a 32 byte nonce constituting a proof-of-work, or the empty
  #   string as a placeholder
  #
  class BlockHeader
    include RLP::Sedes::Serializable

    extend Sedes

    set_serializable_fields(
      prevhash: hash32,
      uncles_hash: hash32,
      coinbase: address,
      state_root: trie_root,
      tx_list_root: trie_root,
      receipts_root: trie_root,
      bloom: int256,
      difficulty: big_endian_int,
      number: big_endian_int,
      gas_limit: big_endian_int,
      gas_used: big_endian_int,
      timestamp: big_endian_int,
      extra_data: binary,
      mixhash: binary,
      nonce: RLP::Sedes::Binary.new(min_length: 8, allow_empty: true)
    )
  end
end
