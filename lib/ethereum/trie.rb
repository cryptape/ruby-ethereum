require 'ethereum/trie/nibble_key'

module Ethereum

  ##
  # A implementation of Merkle Patricia Tree.
  #
  # @see https://github.com/ethereum/wiki/wiki/Patricia-Tree
  #
  class Trie

    NODE_TYPES = %i(blank leaf extension branch).freeze
    NODE_KV_TYPE = %i(leaf extension).freeze

    BRANCH_CARDINAL = 16
    BRANCH_WIDTH = BRANCH_CARDINAL + 1
    KV_WIDTH = 2

    BLANK_NODE = "".freeze
    BLANK_ROOT = Utils.keccak_rlp('').freeze

    class InvalidNode < StandardError; end
    class InvalidNodeType < StandardError; end
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

      raise InvalidNode, "invalid root node" unless @root_node.instance_of?(Array)

      val = FastRLP.encode @root_node
      key = Utils.keccak_256 val

      @db.put key, val
      spv_grabbing(@root_node)

      key
    end
    alias :update_root_hash :root_hash

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
    # Get value from trie.
    #
    # @param key [String]
    #
    # @return [String] BLANK_NODE if does not exist, otherwise node value
    #
    def [](key)
      find @root_node, NibbleKey.from_str(key)
    end

    ##
    # Set value of key.
    #
    # @param key [String]
    # @param value [String]
    #
    def []=(key, value)
      raise ArgumentError, "key must be string" unless key.instance_of?(String)
      raise ArgumentError, "value must be string" unless value.instance_of?(String)

      @root_node = update_and_delete_storage(
        @root_node,
        NibbleKey.from_str(key),
        value
      )

      update_root_hash
    end

    ##
    # Get count of all nodes of the trie.
    #
    def size
      get_size @root_node
    end

    ##
    # clear all tree data
    #
    def clear
      delete_child_storage(@root_node)
      delete_node_storage(@root_node)
      @root_node = BLANK_NODE
    end

    ##
    # Get value inside a node.
    #
    # @param node [Array, BLANK_NODE] node in form of list, or BLANK_NODE
    # @param nbk [NibbleKey] nibble array without terminator
    #
    # @return [String] BLANK_NODE if does not exist, otherwise node value
    #
    def find(node, nbk)
      node_type = get_node_type node

      case node_type
      when :blank
        BLANK_NODE
      when :branch
        return node.last if nbk.empty?

        sub_node = decode_to_node node[nbk[0]]
        find sub_node, nbk[1..-1]
      when :leaf
        node_key = NibbleKey.decode(node[0]).terminate(false)
        nbk == node_key ? node[1] : BLANK_NODE
      when :extension
        node_key = NibbleKey.decode(node[0]).terminate(false)
        if node_key.prefix?(nbk)
          sub_node = decode_to_node node[1]
          find sub_node, nbk[node_key.size..-1]
        else
          BLANK_NODE
        end
      else
        raise InvalidNodeType, "node type must be in #{NODE_TYPES}, given: #{node_type}"
      end
    end

    private

    ##
    # Get counts of (key, value) stored in this and the descendant nodes.
    #
    # TODO: refactor into Node class
    #
    # @param node [Array, BLANK_NODE] node in form of list, or BLANK_NODE
    #
    # @return [Integer]
    #
    def get_size(node)
      case get_node_type(node)
      when :branch
        sizes = node[0,BRANCH_CARDINAL].map {|n| get_size decode_to_node(n) }
        sizes.push(node.last.nil? ? 0 : 1)
        sizes.reduce(0, &:+)
      when :extension
        get_size decode_to_node(node[1])
      when :leaf
        1
      when :blank
        0
      end
    end

    def encode_node(node)
      return BLANK_NODE if node == BLANK_NODE
      raise ArgumentError, "node must be an array" unless node.instance_of?(Array)

      rlp_node = FastRLP.encode node
      return rlp_node if rlp_node.size < 32

      hashkey = Utils.keccak_256 rlp_node
      @db.put hashkey, rlp_node
      spv_storing node

      hashkey
    end

    def decode_to_node(encoded)
      return BLANK_NODE if encoded == BLANK_NODE
      return encoded if encoded.instance_of?(Array)

      RLP.decode(@db.get(encoded))
        .tap {|o| spv_grabbing(o) }
    end

    def update_and_delete_storage(node, key, value)
      old_node = node.dup
      new_node = update_node(node, key, value)
      delete_node_storage(old_node) if old_node != new_node
      new_node
    end

    ##
    # Update item inside a node.
    #
    # If this node is changed to a new node, it's parent will take the
    # responsibility to **store** the new node storage, and delete the old node
    # storage.
    #
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    # @param key [NibbleKey] nibble key without terminator
    # @param value [String] value string
    #
    # @return [Array, BLANK_NODE] new node
    #
    def update_node(node, key, value)
      node_type = get_node_type node

      case node_type
      when :blank
        [key.terminate(true).encode, value]
      when :branch
        if key.empty?
          node.last = value
        else
          new_node = update_and_delete_storage(
            decode_to_node(node[key[0]]),
            key[1..-1],
            value
          )
          node[key[0]] = encode_node new_node
        end

        node
      else # kv node type
        update_kv_node(node, key, value)
      end
    end

    # TODO: refactor this crazy tall guy
    def update_kv_node(node, key, value)
      node_type = get_node_type node
      node_key = NibbleKey.decode(node[0]).terminate(false)
      inner = node_type == :extension

      common_key = node_key.common_prefix(key)
      remain_key = key[common_key.size..-1]
      remain_node_key = node_key[common_key.size..-1]

      if remain_key.empty? && remain_node_key.empty? # target key equals node's key
        if inner
          new_node = update_and_delete_storage(
            decode_to_node(node[1]),
            remain_key,
            value
          )
        else
          return [node[0], value]
        end
      elsif remain_node_key.empty? # target key includes node's key
        if inner
          new_node = update_and_delete_storage(
            decode_to_node(node[1]),
            remain_key,
            value
          )
        else # node is a leaf, we need to replace it with branch node first
          new_node = [BLANK_NODE] * BRANCH_WIDTH
          new_node[-1] = node[1]
          new_node[remain_key[0]] = encode_node([
            remain_key[1..-1].terminate(true).encode,
            value
          ])
        end
      else
        new_node = [BLANK_NODE] * BRANCH_WIDTH

        if remain_node_key.size == 1 && inner
          new_node[remain_node_key[0]] = node[1]
        else
          new_node[remain_node_key[0]] = encode_node([
            remain_node_key[1..-1].terminate(!inner).encode,
            node[1]
          ])
        end

        if remain_key.empty? # node's key include target key
          new_node[-1] = value
        else
          new_node[remain_key[0]] = encode_node([
            remain_key[1..-1].terminate(true).encode,
            value
          ])
        end
      end

      if common_key.empty?
        new_node
      else
        [node_key[0, common_key.size].encode, encode_node(new_node)]
      end
    end

    ##
    # Delete node storage.
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
      # \@db.delete encoded
    end

    def delete_child_storage(node)
      node_type = get_node_type node
      case node_type
      when :branch
        node[0,BRANCH_CARDINAL].each {|item| delete_child_storage decode_to_node(item) }
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
      when KV_WIDTH # [k,v]
        NibbleKey.decode(node[0]).terminate? ? :leaf : :extension
      when BRANCH_WIDTH # [k0, ... k15, v]
        :branch
      else
        raise InvalidNode, "node size must be #{KV_WIDTH} or #{BRANCH_WIDTH}"
      end
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
