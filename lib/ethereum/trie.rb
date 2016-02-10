require 'ethereum/trie/nibble_key'

module Ethereum

  ##
  # A implementation of Merkle Patricia Tree.
  #
  # @see https://github.com/ethereum/wiki/wiki/Patricia-Tree
  #
  class Trie
    include Enumerable

    NODE_TYPES = %i(blank leaf extension branch).freeze
    NODE_KV_TYPE = %i(leaf extension).freeze

    BRANCH_CARDINAL = 16
    BRANCH_WIDTH = BRANCH_CARDINAL + 1
    KV_WIDTH = 2

    BLANK_NODE = "".freeze
    BLANK_ROOT = Utils.keccak_rlp('').freeze

    class InvalidNode < StandardError; end
    class InvalidNodeType < StandardError; end

    ##
    # It presents a hash like interface.
    #
    # @param db [Object] key value database
    # @param root_hash [String] blank or trie node in form of [key, value] or
    #   [v0, v1, .. v15, v]
    #
    def initialize(db, root_hash=BLANK_ROOT)
      @db = db
      set_root_hash root_hash
    end

    ##
    # @return empty or 32 bytes string
    #
    def root_hash
      # TODO: can I memoize computation below?
      return BLANK_ROOT if @root_node == BLANK_NODE

      raise InvalidNode, "invalid root node" unless @root_node.instance_of?(Array)

      val = FastRLP.encode @root_node
      key = Utils.keccak_256 val

      @db.put key, val
      #spv_grabbing(@root_node)

      key
    end
    alias :update_root_hash :root_hash

    def set_root_hash(hash)
      raise TypeError, "root hash must be String" unless hash.instance_of?(String)
      raise ArgumentError, "root hash must be 0 or 32 bytes long" unless [0,32].include?(hash.size)

      if hash == BLANK_ROOT
        @root_node = BLANK_NODE
      else
        @root_node = decode_to_node hash
      end
    end

    def root_hash_valid?
      return true if @root_hash == BLANK_ROOT
      return @db.include?(@root_hash)
    end

    ##
    # Get value from trie.
    #
    # @param key [String]
    #
    # @return [String] BLANK_NODE if does not exist, otherwise node value
    #
    def [](key)
      find @root_node, NibbleKey.from_string(key)
    end
    alias :get :[]

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
        NibbleKey.from_string(key),
        value
      )

      update_root_hash
    end
    alias :set :[]=

    ##
    # Delete value at key.
    #
    # @param key [String] a string with length of [0,32]
    #
    def delete(key)
      raise ArgumentError, "key must be string" unless key.instance_of?(String)
      raise ArgumentError, "max key size is 32" if key.size > 32

      @root_node = delete_and_delete_storage(
        @root_node,
        NibbleKey.from_string(key)
      )

      update_root_hash
    end

    ##
    # Convert to hash.
    #
    def to_h
      hash = {}

      to_hash(@root_node).each do |k, v|
        key = k.terminate(false).to_string
        hash[key] = v
      end

      hash
    end

    def each(&block)
      to_h.each(&block)
    end

    def has_key?(key)
      self[key] != BLANK_NODE
    end
    alias :include? :has_key?

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
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    # @param nbk [Array] nibble array without terminator
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
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
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
      #spv_storing node

      hashkey
    end

    def decode_to_node(encoded)
      return BLANK_NODE if encoded == BLANK_NODE
      return encoded if encoded.instance_of?(Array)

      RLP.decode(@db.get(encoded))
        #.tap {|o| spv_grabbing(o) }
    end

    # TODO: refactor, abstract delete storage logic
    def update_and_delete_storage(node, key, value)
      old_node = node.dup
      new_node = update_node(node, key, value)
      delete_node_storage(old_node) if old_node != new_node
      new_node
    end

    def delete_and_delete_storage(node, key)
      old_node = node.dup
      new_node = delete_node(node, key)
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
    # @param key [Array] nibble key without terminator
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
    # Delete item inside node.
    #
    # If this node is changed to a new node, it's parent will take the
    # responsibility to **store** the new node storage, and delete the old node
    # storage.
    #
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    # @param key [Array] nibble key without terminator. key maybe empty
    #
    # @return new node
    #
    def delete_node(node, key)
      case get_node_type(node)
      when :blank
        BLANK_NODE
      when :branch
        delete_branch_node(node, key)
      else # kv type
        delete_kv_node(node, key)
      end
    end

    def delete_branch_node(node, key)
      if key.empty?
        node[-1] = BLANK_NODE
        return normalize_branch_node(node)
      else
        new_sub_node = delete_and_delete_storage decode_to_node(node[key[0]]), key[1..-1]
        encoded_new_sub_node = encode_node new_sub_node

        return node if encoded_new_sub_node == node[key[0]]

        node[key[0]] = encoded_new_sub_node
        return normalize_branch_node(node) if encoded_new_sub_node == BLANK_NODE

        node
      end
    end

    def delete_kv_node(node, key)
      node_type = get_node_type node
      raise ArgumentError, "node type is not one of key-value type (#{NODE_KV_TYPE})" unless NODE_KV_TYPE.include?(node_type)

      node_key = NibbleKey.decode(node[0]).terminate(false)

      # key not found
      return node unless key.prefix?(node_key)

      if node_type == :leaf
        key == node_key ? BLANK_NODE : node
      else # :extension
        new_sub_node = delete_and_delete_storage decode_to_node(node[1]), key[node_key.size..-1]

        return node if encode_node(new_sub_node) == node[1]
        return BLANK_NODE if new_sub_node == BLANK_NODE

        raise InvalidNode, "new sub node must be array" unless new_sub_node.instance_of?(Array)

        new_sub_node_type = get_node_type new_sub_node

        case new_sub_node_type
        when :branch
          [node_key.encode, encode_node(new_sub_node)]
        when *NODE_KV_TYPE
          new_key = node_key + NibbleKey.decode(new_sub_node[0])
          [new_key.encode, new_sub_node[1]]
        else
          raise InvalidNodeType, "invalid kv sub node type #{new_sub_node_type}"
        end
      end
    end

    def normalize_branch_node(node)
      non_blank_items = node.each_with_index.select {|(x, i)| x != BLANK_NODE }

      raise ArgumentError, "node must has at least 1 non blank item" unless non_blank_items.size > 0
      return node if non_blank_items.size > 1

      non_blank_index = non_blank_items[0][1]

      # if value is the only non blank item, convert it into a kv node
      return [NibbleKey.new([]).terminate(true).encode, node.last] if non_blank_index == NibbleKey::NIBBLE_TERMINATOR

      sub_node = decode_to_node node[non_blank_index]
      sub_node_type = get_node_type sub_node

      case sub_node_type
      when :branch
        [NibbleKey.new([non_blank_index]).encode, encode_node(sub_node)]
      when *NODE_KV_TYPE
        new_key = NibbleKey.decode(sub_node[0]).unshift(non_blank_index)
        [new_key.encode, sub_node[1]]
      else
        raise InvalidNodeType, "invalid branch sub node type #{sub_node_type}"
      end
    end

    ##
    # Delete node storage.
    #
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    #
    def delete_node_storage(node)
      return if node == BLANK_NODE
      raise ArgumentError, "node must be Array or BLANK_NODE" unless node.instance_of?(Array)

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

    ##
    # Convert [key, value] stored in this and the descendant nodes to hash.
    #
    # @param node [Array, BLANK_NODE] node in form of array, or BLANK_NODE
    #
    # @return [Hash] equivalent hash. Hash key is in full form (Array).
    def to_hash(node)
      node_type = get_node_type node

      case node_type
      when :blank
        {}
      when :branch
        hash = {}

        16.times do |i|
          sub_hash = to_hash decode_to_node(node[i])
          sub_hash.each {|k, v| hash[[i] + k] = v }
        end

        hash[NibbleKey.terminator] = node.last if node.last
        hash
      when *NODE_KV_TYPE
        nibbles = NibbleKey.decode(node[0]).terminate(false)

        sub_hash = node_type == :extension ?
          to_hash(decode_to_node(node[1])) : {NibbleKey.terminator => node[1]}

        {}.tap do |hash|
          sub_hash.each {|k, v| hash[nibbles + k] = v }
        end
      else
        # do nothing
      end
    end
  end

end
