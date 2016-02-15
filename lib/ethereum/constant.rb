module Ethereum
  module Constant
    BYTE_EMPTY = "".b.freeze
    BYTE_ZERO = "\x00".b.freeze
    BYTE_ONE  = "\x01".b.freeze

    UINT_MAX = 2**256 - 1
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255

    ADDRESS_ZERO = ("\x00"*20).b.freeze

    HASH_ZERO = ("\x00"*32).b.freeze
  end
end
