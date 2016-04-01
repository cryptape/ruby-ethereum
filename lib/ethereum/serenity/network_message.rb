# -*- encoding : ascii-8bit -*-

module Ethereum
  class NetworkMessage

    include RLP::Sedes::Serializable

    set_serializable_fields(
      type: Sedes.big_endian_int,
      args: RLP::Sedes::CountableList.new(Sedes.binary)
    )

    TYPES = %i(list block bet bet_request transaction getblock getblocks blocks).each_with_index.map {|t, i| [t, i] }.to_h.freeze

    def initialize(*args)
      if args.first.instance_of?(Symbol)
        super(TYPES[args[0]], args[1])
      else
        super(*args)
      end
    end

  end
end

