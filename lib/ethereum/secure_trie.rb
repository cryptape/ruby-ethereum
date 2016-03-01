# -*- encoding : ascii-8bit -*-

require 'forwardable'

module Ethereum
  class SecureTrie

    extend Forwardable
    def_delegators :@trie, :root_hash, :set_root_hash, :root_hash_valid?, :process_epoch, :commit_death_row, :revert_epoch, :has_key?, :include?, :size, :to_h, :db

    def initialize(trie)
      @trie = trie
      @db = trie.db
    end

    def [](k)
      @trie[Utils.keccak256(k)]
    end
    alias :get :[]

    def []=(k, v)
      h = Utils.keccak256 k
      @db.put h, k
      @trie[h] = v
    end
    alias :set :[]=

    def delete(k)
      @trie.delete Utils.keccak256(k)
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
