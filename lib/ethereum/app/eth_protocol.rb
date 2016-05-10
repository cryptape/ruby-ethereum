# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class ETHProtocolError < StandardError; end

    ##
    # DEV Ethereum Wire Protocol
    #
    # @see https://github.com/ethereum/wiki/wiki/Ethereum-Wire-Protocol
    # @see https://github.com/ethereum/go-ethereum/blob/develop/eth/protocol.go#L15
    #
    class ETHProtocol < DEVp2p::BaseProtocol

      ##
      # Inform a peer of it's current ethereum state. This message should be
      # sent after the initial handshake and prior to any ethereum related
      # messages.
      #
      class Status < DEVp2p::Command
        cmd_id 0

        structure(
          eth_version: RLP::Sedes.big_endian_int,
          network_id: RLP::Sedes.big_endian_int,
          chain_difficulty: RLP::Sedes.big_endian_int,
          chain_head_hash: RLP::Sedes.binary,
          genesis_hash: RLP::Sedes.binary
        )

        attr :sent

        def initialize
          super
          @sent = false
        end

        def create(proto, chain_difficulty, chain_head_hash, genesis_hash)
          @sent = true
          network_id = proto.service.app.config[:eth].fetch(:network_id, proto.network_id)
          [proto.version, network_id, chain_difficulty, chain_head_hash, genesis_hash]
        end
      end

      ##
      # Specify one or more new blocks which have appeared on the network.
      #
      # The list may contain 256 hashes at most. To be maximally helpful,
      # nodes should inform peers of all blocks that they may not be aware of.
      #
      # Including hashes that the sending peer could reasonably be considered
      # to know (due to the fact they were previously informed of because that
      # node has itself advertised knowledge of the hashes through
      # NewBlockHashes) is considered Bad Form, and may reduce the reputation
      # of the sending node.
      #
      # Including hashes that the sending node later refuses to honour with a
      # proceeding GetBlocks message is considered Bad Form, and may reduce
      # the reputation of the sending node.
      #
      class NewBlockHashes < DEVp2p::Command
        cmd_id 1
        structure RLP::Sedes::CountableList.new(RLP::Sedes.binary)
      end

      ##
      # Specify (a) transaction(s) that the peer should make sure is included
      # on its transaction queue.
      #
      # The items in the list (following the first item 0x12) are transactions
      # in the format described in the main Ethereum specification. Nodes must
      # not resend the same transaction to a peer in the same session. This
      # packet must contain at least one (new) transaction.
      #
      class Transactions < DEVp2p::Command
        cmd_id 2
        structure RLP::Sedes::CountableList.new(Transaction)

        def self.decode_payload(rlp_data)
          txs = []
          RLP.decode_lazy(rlp_data).each_with_index do |tx, i|
            txs.push Transaction.deserialize tx
            sleep 0.0001 if i % 10 == 0
          end
          txs
        end
      end

      ##
      # Requests a BlockHashes message of at most maxBlocks entries, of block
      # hashes from the blockchain, starting at the parent of block hash. Does
      # not require the peer to give maxBlocks hashes - they could give
      # somewhat fewer.
      #
      class GetBlockHashes < DEVp2p::Command
        cmd_id 3

        structure(
          child_block_hash: RLP::Sedes.binary,
          count: RLP::Sedes.big_endian_int
        )
      end

      ##
      # Gives a series of hashes of blocks (each the child of the next). This
      # implies that the blocks are ordered from youngest to oldest.
      #
      class BlockHashes < DEVp2p::Command
        cmd_id 4
        structure RLP::Sedes::CountableList.new(RLP::Sedes.binary)
      end

      ##
      # Requests a Blocks message detailing a number of blocks to be sent, each
      # referred to by a hash.
      #
      # Note: Don't expect that the peer necessarily give you all these blocks
      # in a single message - you might have to re-request them.
      #
      class GetBlocks < DEVp2p::Command
        cmd_id 5
        structure RLP::Sedes::CountableList.new(RLP::Sedes.binary)
      end

      ##
      # Specify (a) block(s) as an answer to GetBlocks. The items in the list
      # (following the message ID) are blocks in the format described in the
      # main Ethereum specification. This may validly contain no blocks if no
      # blocks were able to be returned for the GetBlocks query.
      #
      class Blocks < DEVp2p::Command
        cmd_id 6
        structure RLP::Sedes::CountableList.new(Block)

        class <<self
          def encode_payload(list_of_rlp)
            RLP.encode(list_of_rlp.map {|x| RLP::Data.new(x) }, infer_serializer: false)
          end

          def decode_payload(rlp_data)
            blocks = []
            RLP.decode_lazy(rlp_data).map {|block| TransientBlock.new block }
          end
        end
      end

      ##
      # Specify a single block that the peer should know about.
      #
      # The composite item in the list (following the message ID) is a block in
      # the format described in the main Ethereum specification.
      #
      class NewBlock < DEVp2p::Command
        cmd_id 7

        structure(
          block: Block,
          chain_difficulty: RLP::Sedes.big_endian_int
        )

        def self.decode_payload(rlp_data)
          ll = RLP.decode_lazy rlp_data
          raise AssertError unless ll.size == 2

          transient_block = TransientBlock.new ll[0], Time.now
          difficulty = RLP::Sedes.big_endian_int.deserialize ll[1]

          {block: transient_block, chain_difficulty: difficulty}
        end
      end

      ##
      # Requires peer to reply with a BlockHashes message.
      #
      # Message should contain block with that of number number on the
      # canonical chain. Should also be followed by subsequent blocks, on the
      # same chain, detailing a number of the first block hash and a total of
      # hashes to be sent. Returned hash list must be ordered by block number
      # in ascending order.
      #
      class GetBlockHashesFromNumber < DEVp2p::Command
        cmd_id 8

        structure(
          number: RLP::Sedes.big_endian_int,
          count: RLP::Sedes.big_endian_int
        )
      end

      name 'eth'
      protocol_id 1
      max_cmd_id 15
      version 61

      MAX_GETBLOCKS_COUNT = 64
      MAX_GETBLOCKHASHES_COUNT = 2048

      attr :network_id

      def initialize(peer, service)
        @config = peer.config
        @network_id = 0

        super(peer, service)
      end

    end

  end
end
