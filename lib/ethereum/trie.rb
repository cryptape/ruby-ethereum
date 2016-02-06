module Ethereum

  ##
  # A implementation of Merkle Patricia Tree.
  #
  # @see https://github.com/ethereum/wiki/wiki/Patricia-Tree
  #
  class Trie

    NIBBLE_TERM_FLAG  = 0b0010
    NIBBLE_ODD_FLAG   = 0b0001
    NIBBLE_TERMINATOR = 16

    NODE_TYPES = %i(blank leaf extension branch).freeze
    NODE_KV_TYPE = %i(leaf extension).freeze

    BLANK_NODE = "".freeze
    BLANK_ROOT = Utils.keccak_rlp('').freeze

    class InvalidNode < StandardError; end
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

    ##
    # @return empty or 32 bytes string
    #
    def root_hash
      # TODO: can I memoize computation below?
      return @transient_root_hash if @transient
      return BLANK_ROOT if @root_node == BLANK_NODE

      raise InvalidNode, "invalid root node" unless Utils.list?(@root_node)

      val = FastRLP.encode @root_node
      key = Utils.keccak_256 val

      @db.put key, val
      spv_grabbing(@root_node)

      key
    end

    def set_root_hash(hash)
      raise TypeError, "root hash must be String" unless hash.instance_of?(String)
      raise ArgumentError, "root hash must be 0 or 32 bytes long" unless [0,32].include?(hash.size)

      if @transient
        @transient_root_hash = hash
      elsif hash == BLANK_ROOT
        @root_node = BLANK_NODE
      else
        @root_node = decode_to_node hash
      end
    end

    ##
    # clear all tree data
    #
    def clear
      delete_child_storage(@root_node)
      delete_node_storage(@root_node)
      @root_node = BLANK_NODE
    end

    private

    def encode_node(node)
      # TODO
    end

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

    ##
    # delete storage
    #
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    #
    def delete_node_storage(node)
      return if node == BLANK_NODE
      raise ArgumentError, "node must be Array or BLANK_NODE"

      encoded = encode_node node
      return if encoded.size < 32

      # FIXME: in current trie implementation two nodes can share identical
      # subtree thus we can not safely delete nodes for now
      #
      # @db.delete encoded
    end

    def delete_child_storage(node)
      node_type = get_node_type node
      case node_type
      when :branch
        node[0,16].each {|item| delete_child_storage decode_to_node(item) }
      when :extension
        delete_child_storage decode_to_node(node[1])
      else
        # do nothing
      end
    end

    ##
    # get node type and content
    #
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    #
    # @return [Symbol] node type
    #
    def get_node_type(node)
      return :blank if node == BLANK_NODE

      case node.size
      when 2 # [k,v]
        nibbles = unpack_to_nibbles node[0]
        has_terminator = (nibbles && nibbles.last == NIBBLE_TERMINATOR)
        has_terminator ? :leaf : :extension
      when 17 # [k0, ... k15, v]
        :branch
      else
        raise InvalidNode, "node size must be 2 or 17"
      end
    end

    ###
    # unpack packed binary data to nibbles.
    #
    # @param bindata [String] binary packed from nibbles
    #
    # @return [Array] nibbles array, may have a terminator
    #
    def unpack_to_nibbles(bindata)
      o = str_to_nibbles bindata
      flags = o[0]

      o.push NIBBLE_TERMINATOR if flags & NIBBLE_TERM_FLAG == 1

      fill = flags & NIBBLE_ODD_FLAG == 1 ? 1 : 2
      o[fill..-1]
    end

  end

end
