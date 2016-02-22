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

    extend self
  end
end

# TODO: benchmark
