# -*- encoding : ascii-8bit -*-

module Ethereum
  module FastRLP
    include RLP::Encode

    ##
    # RLP encode (a nested list of ) bytes.
    #
    def encode_nested_bytes(item)
      if item.instance_of?(String)
        return item if item.size == 1 && item.ord < PRIMITIVE_PREFIX_OFFSET
        prefix = length_prefix item.size, PRIMITIVE_PREFIX_OFFSET
      else # list
        item = item.map {|x| encode_nested_bytes(x) }.join
        prefix = length_prefix item.size, LIST_PREFIX_OFFSET
      end

      "#{prefix}#{item}"
    end

    ##
    # Alias to encode_nested_bytes, override default encode.
    #
    def encode(item)
      encode_nested_bytes item
    end

    def decode(rlp)
      o = []
      pos = 0

      type, len, pos = consume_length_prefix rlp, pos
      return rlp[pos, len] if type != :list

      while pos < rlp.size
        _, _len, _pos = consume_length_prefix rlp, pos
        to = _len + _pos
        o.push decode(rlp[pos...to])
        pos = to
      end

      o
    end

    ##
    # Read a length prefix from an RLP string.
    #
    # * `rlp` - the rlp string to read from
    # * `start` - the position at which to start reading
    #
    # Returns an array `[type, length, end]`, where `type` is either `:str`
    # or `:list` depending on the type of the following payload, `length` is
    # the length of the payload in bytes, and `end` is the position of the
    # first payload byte in the rlp string (thus the end of length prefix).
    #
    def consume_length_prefix(rlp, start)
      b0 = rlp[start].ord

      if b0 < PRIMITIVE_PREFIX_OFFSET # single byte
        [:str, 1, start]
      elsif b0 < PRIMITIVE_PREFIX_OFFSET + SHORT_LENGTH_LIMIT # short string
        [:str, b0 - PRIMITIVE_PREFIX_OFFSET, start + 1]
      elsif b0 < LIST_PREFIX_OFFSET # long string
        ll = b0 - PRIMITIVE_PREFIX_OFFSET - SHORT_LENGTH_LIMIT + 1
        l = big_endian_to_int rlp[(start+1)...(start+1+ll)]
        [:str, l, start+1+ll]
      elsif b0 < LIST_PREFIX_OFFSET + SHORT_LENGTH_LIMIT # short list
        [:list, b0 - LIST_PREFIX_OFFSET, start + 1]
      else # long list
        ll = b0 - LIST_PREFIX_OFFSET - SHORT_LENGTH_LIMIT + 1
        l = big_endian_to_int rlp[(start+1)...(start+1+ll)]
        [:list, l, start+1+ll]
      end
    end

    extend self
  end
end

# TODO: benchmark
