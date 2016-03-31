# -*- encoding : ascii-8bit -*-

module Ethereum
  module Constant

    BYTE_EMPTY = "".freeze
    BYTE_ZERO = "\x00".freeze
    BYTE_ONE  = "\x01".freeze

    WORD_ZERO = ("\x00"*32).freeze
    HASH_ZERO = WORD_ZERO

    TT32  = 2**32
    TT256 = 2**256
    TT64M1 = 2**64 - 1

    UINT_MAX = 2**256 - 1
    UINT_MIN = 0
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255

    PUBKEY_ZERO = [0,0].freeze
    PRIVKEY_ZERO = WORD_ZERO

    ##
    # Global Parameters
    #

    BLKTIME = 3.75
    TXGAS = 1
    TXINDEX = 2
    GAS_REMAINING = 3
    BLOOM = 2**32
    GASLIMIT = 4712388 # Pau million

    ENTER_EXIT_DELAY = 110 # must be set in Casper contract as well
    VALIDATOR_ROUNDS = 5 # must be set in Casper contract as well

    MAXSHARDS = 65536
    SHARD_BYTES = RLP::Sedes.big_endian_int.serialize(MAXSHARDS-1).size
    ADDR_BASE_BYTES = 20
    ADDR_BYTES = ADDR_BASE_BYTES + SHARD_BYTES

    UNHASH_MAGIC_BYTES = "unhash:"

  end
end
