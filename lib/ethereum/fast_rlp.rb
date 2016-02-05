module Ethereum
  module FastRLP
    include RLP::Encode

    ##
    # RLP encode (a nested list of ) bytes.
    #
    def encode_nested_bytes(item)
      if primitive?(item) && bytes?(item)
        return item if item.size == 1 && item.ord < PRIMITIVE_PREFIX_OFFSET
        prefix = length_prefix item.size, PRIMITIVE_PREFIX_OFFSET
      elsif list?(item)
        item = item.map {|x| encode_nested_bytes(x) }.join
        prefix = length_prefix item.size, LIST_PREFIX_OFFSET
      else
        raise ArgumentError, "item must be bytes or (nested) array of bytes"
      end

      "#{prefix}#{item}"
    end

    extend self
  end
end

# TODO: benchmark
