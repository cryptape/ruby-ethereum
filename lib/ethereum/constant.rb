# -*- encoding : ascii-8bit -*-

module Ethereum
  module Constant
    BYTE_EMPTY = "".freeze
    BYTE_ZERO = "\x00".freeze
    BYTE_ONE  = "\x01".freeze

    UINT_MAX = 2**256 - 1
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255

    ADDRESS_BLANK = ''.freeze
    ADDRESS_ZERO = ("\x00"*20).freeze

    HASH_ZERO = ("\x00"*32).freeze
  end
end
