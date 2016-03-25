# -*- encoding : ascii-8bit -*-

module Ethereum
  module Constant

    BYTE_EMPTY = "".freeze
    BYTE_ZERO = "\x00".freeze
    BYTE_ONE  = "\x01".freeze

    TT32  = 2**32
    TT256 = 2**256
    TT64M1 = 2**64 - 1

    UINT_MAX = 2**256 - 1
    UINT_MIN = 0
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255

    HASH_ZERO = ("\x00"*32).freeze

    PUBKEY_ZERO = [0,0].freeze
    PRIVKEY_ZERO = ("\x00"*32).freeze

    MAXSHARDS = 2**16 # 65536
    SHARD_BYTES = RLP::Sedes.big_endian_int.serialize(MAXSHARDS - 1).size
    ADDR_BASE_BYTES = 20
    ADDR_BYTES = SHARD_BYTES + ADDR_BASE_BYTES
  end
end
