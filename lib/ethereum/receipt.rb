# -*- encoding : ascii-8bit -*-

module Ethereum
  class Receipt
    include RLP::Sedes::Serializable

    extend Sedes

    set_serializable_fields(
      state_root: trie_root,
      gas_used: big_endian_int,
      bloom: int256,
      logs: RLP::Sedes::CountableList.new(Log)
    )

    # initialize(state_root, gas_used, logs, bloom: nil)
    def initialize(*args)
      h = normalize_args args
      super(h)
      raise ArgumentError, "Invalid bloom filter" if h[:bloom] && h[:bloom] != self.bloom
    end

    def bloom
      bloomables = logs.map {|l| l.bloomables }
      Bloom.from_array bloomables.flatten
    end

    private

    def normalize_args(args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      field_set = %i(state_root gas_used logs bloom) # different order than serializable fields

      h = {}
      fields = field_set[0,args.size]
      fields.zip(args).each do |(field, arg)|
        h[field] = arg
        field_set.delete field
      end

      options.each do |field, value|
        if field_set.include?(field)
          h[field] = value
          field_set.delete field
        end
      end

      field_set.each {|field| h[field] = nil }
      h
    end

  end
end
