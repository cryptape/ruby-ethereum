# -*- encoding : ascii-8bit -*-

module Ethereum
  class Transaction

    include RLP::Sedes::Serializable
    extend Sedes

    set_serializable_fields(
      addr: address,
      gas: big_endian_int,
      left_bound: big_endian_int,
      right_bound: big_endian_int,
      data: binary,
      code: binary
    )

    include Constant

    def initialize(addr, gas, left_bound: 0, right_bound: MAXSHARDS, data: BYTE_EMPTY, code: BYTE_EMPTY)
      addr = addr || Utils.shardify(generate_address(code), left_bound)

      super(addr: addr, gas: gas,
            left_bound: left_bound, right_bound: right_bound,
            data: data, code: code)

      validate!
    end

    def full_hash
      Utils.keccak256_rlp self
    end

    def intrinsic_gas
      num_zero_bytes = data.count BYTE_ZERO
      num_none_zero_bytes = data.size - num_zero_bytes
      Opcodes::GTXCOST +
        num_zero_bytes * Opcodes::GTXDATAZERO +
        num_none_zero_bytes * Opcodes::GTXDATANONZERO +
        code.size * Opcodes::GCONTRACTBYTE
    end

    def exec_gas
      gas - intrinsic_gas
    end

    private

    def validate!
      raise AssertError, "invalid address" unless addr.size == ADDR_BYTES
      raise AssertError, "invalid address" unless code.empty? || Utils.shardify(generate_address(code), left_bound) == addr
      raise AssertError, "not enough gas" unless exec_gas >= 0
      raise AssertError, "left_bound must be integer" unless left_bound.is_a?(Integer)
      raise AssertError, "right_bound must be integer" unless right_bound.is_a?(Integer)
    end

    def generate_address(code)
      Utils.keccak256(Address::ZERO + code)[12..-1]
    end

  end
end
