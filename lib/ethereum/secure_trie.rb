require 'forwardable'

module Ethereum
  class SecureTrie

    extend Forwardable
    def_delegators :@trie, :root_hash, :set_root_hash, :root_hash_valid?, :process_epoch, :commit_death_row, :revert_epoch

    def initialize(trie)
      @trie = trie
      @db = trie.db
    end

    def [](k)
      @trie[Utils.keccak_256(k)]
    end

    def []=(k, v)
      h = Utils.keccak_256 k
      @db.put h, k
      @trie[h] = v
    end

    def delete(k)
      @trie.delete Utils.keccak_256(k)
    end

    def to_h
      o = {}
      @trie.to_h.each do |h, v|
        k = @db.get h
        o[k] = v
      end
      o
    end

    def each(&block)
      @trie.each do |h, v|
        k = @db.get h
        block.call k, v
      end
    end

  end
end
