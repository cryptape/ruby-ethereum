module Ethereum

  ##
  # A implementation of Merkle Patricia Tree.
  #
  # @see https://github.com/ethereum/wiki/wiki/Patricia-Tree
  #
  class Trie

    BLANK_NODE = "".freeze
    BLANK_ROOT = Utils.keccak_rlp('').freeze

    class InvalidSPVProof < StandardError; end

    ##
    # It presents a hash like interface.
    #
    # @param db [Object] key value database
    # @param root_hash [String] blank or trie node in form of [key, value] or
    #   [v0, v1, .. v15, v]
    #
    def initialize(db, root_hash: BLANK_ROOT, transient: false)
      @db = db
      @transient = transient
      #TODO: update/get/delete all raise exception if transient

      @proof = SPVProof.new

      set_root_hash root_hash
    end

    def set_root_hash(root_hash)
      raise TypeError, "root hash must be String" unless root_hash.instance_of?(String)
      raise ArgumentError, "root hash must be 0 or 32 bytes long" unless [0,32].include?(root_hash.size)

      if @transient
        @transient_root_hash = root_hash
      elsif root_hash == BLANK_ROOT
        @root_node = BLANK_NODE
      else
        @root_node = decode_to_node root_hash
      end
    end

    private

    def decode_to_node(encoded)
      return BLANK_NODE if encoded == BLANK_NODE
      return encoded if encoded.instance_of?(Array)

      RLP.decode(@db.get(encoded))
        .tap {|o| spv_grabbing(o) }
    end

    def spv_grabbing(node)
      return unless @proof.proving?

      case @proof.mode
      when :recording
        @proof.add_node node.dup
      when :verifying
        raise InvalidSPVProof.new("Proof invalid!") unless @proof.nodes.include?(FastRLP.encode(node))
      else
        raise "Cannot handle proof mode: #{@proof.mode}"
      end
    end

    def spv_storing(node)
      return unless @proof.proving

      case @proof.mode
      when :recording
        @proof.add_exempt node.dup
      when :verifying
        @proof.add_node node.dup
      else
        raise "Cannot handle proof mode: #{@proof.mode}"
      end
    end

  end

end
