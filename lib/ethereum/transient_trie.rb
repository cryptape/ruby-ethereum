# -*- encoding : ascii-8bit -*-

module Ethereum
  class TransientTrie < Trie

    class InvalidTransientTrieOperation < StandardError; end

    def transient_trie_exception(*args)
      raise InvalidTransientTrieOperation
    end

    alias :[] :transient_trie_exception
    alias :[]= :transient_trie_exception
    alias :delete :transient_trie_exception

    def root_hash
      @transient_root_hash
    end

    def set_root_hash(hash)
      raise TypeError, "root hash must be String" unless hash.instance_of?(String)
      raise ArgumentError, "root hash must be 0 or 32 bytes long" unless [0,32].include?(hash.size)

      @transient_root_hash = hash
    end

  end
end
