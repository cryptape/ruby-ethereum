# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class TransientBlock
      include RLP::Sedes::Serializable

      set_serializable_fields(
        header: BlockHeader,
        transaction_list: RLP::Sedes::CountableList.new(Transaction),
        uncles: RLP::Sedes::CountableList.new(BlockHeader)
      )

      attr :newblock_timestamp

      def initialize(block_data, newblock_timestamp=0)
        @newblock_timestamp = newblock_timestamp

        header = BlockHeader.deserialize block_data[0]
        transaction_list = RLP::Sedes::CountableList.new(Transaction).deserialize block_data[1]
        uncles = RLP::Sedes::CountableList.new(BlockHeader).deserialize block_data[2]
        super(header, transaction_list, uncles)
      end

      def to_block(env, parent=nil)
        Block.new header: header, transaction_list: transaction_list, uncles: uncles, env: env, parent: parent
      end

      def full_hash_hex
        header.full_hash_hex
      end

      def to_s
        "<TransientBlock(##{header.number} #{header.full_hash_hex[0,8]})"
      end
      alias inspect to_s

    end

  end
end
