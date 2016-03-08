# -*- encoding : ascii-8bit -*-

module Ethereum
  class PruningTrie < Trie
    # TODO: pruning trie implementation

    def clear_all(node=nil)
      if node.nil?
        node = @root_node
        delete_node_storage node
      end

      return if node == BLANK_NODE

      node_type = get_node_type node
      delete_node_storage node

      if NODE_KV_TYPE.include?(node_type)
        value_is_node = node_type == :extension
        clear_all decode_to_node(node[1]) if value_is_node
      elsif node_type == :branch
        16.times do |i|
          clear_all decode_to_node(node[i])
        end
      end
    end
  end
end
