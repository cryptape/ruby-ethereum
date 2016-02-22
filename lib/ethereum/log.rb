# -*- encoding : ascii-8bit -*-

module Ethereum
  class Log
    include RLP::Sedes::Serializable

    set_serializable_fields(
      address: Sedes.address,
      topics: RLP::Sedes::CountableList.new(Sedes.int32),
      data: Sedes.binary
    )

    def initialize(address, topics, data)
      raise ArgumentError, "invalid address: #{address}" unless address.size == 20 || address.size == 40

      address = Utils.decode_hex(address) if address.size == 40
      serializable_initialize(address, topics, data)
    end

    def bloomables
      topics.map {|t| Sedes.int32.serialize(t) }.unshift(address)
    end

    def to_h
      { bloom: Utils.encode_hex(Bloom.b256(Bloom.from_array(bloomables))),
        address: Utils.encode_hex(address),
        data: "0x#{Utils.encode_hex(data)}",
        topics: topics.map {|t| Utils.encode_hex(Sedes.int32.serialize(t)) }
      }
    end

    def to_s
      "#<#{self.class.name}:#{object_id} address=#{Utils.encode_hex(address)} topics=#{topics} data=#{data}>"
    end
    alias :inspect :to_s

  end
end
