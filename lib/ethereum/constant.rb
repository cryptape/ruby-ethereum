module Ethereum
  module Constant
    BYTE_ZERO = "\x00".b.freeze
    BYTE_ONE  = "\x01".b.freeze

    UINT_MAX = 2**256 - 1
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255
  end
end
