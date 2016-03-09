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
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255

    HASH_ZERO = ("\x00"*32).freeze

    PUBKEY_ZERO = [0,0].freeze
    PRIVKEY_ZERO = ("\x00"*32).freeze

  end
end
