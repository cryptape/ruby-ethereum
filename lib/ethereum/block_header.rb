module Ethereum

  ##
  # A block header.
  #
  # If the block with this header exists as an instance of {Block}, the
  # connection can be made explicit by setting `BlockHeader.block`. Then,
  # `BlockHeader.state_root`, `BlockHeader.tx_list_root` and
  # `BlockHeader.receipts_root` always refer to the up-to-date value in the
  # block instance.
  #
  # * `@block` - an instance of {Block} or `nil`
  # * `@prevhash` - the 32 byte hash of the previous block
  # * `@uncles_hash` - the 32 byte hash of the RLP encoded list of uncle headers
  # * `@coinbase` - the 20 byte coinbase address
  # * `@state_root` - the root of the block's state trie
  # * `@tx_list_root` - the root of the block's transaction trie
  # * `@receipts_root` - the root of the block's receipts trie
  # * `@bloom` - bloom filter
  # * `@difficulty` - the block's difficulty
  # * `@number` - the number of ancestors of this block (0 for the genesis block)
  # * `@gas_limit` - the block's gas limit
  # * `@gas_used` - the total amount of gas used by all transactions in this block
  # * `@timestamp` - a UNIX timestamp
  # * `@extra_data` - up to 1024 bytes of additional data
  # * `@nonce` - a 8 byte nonce constituting a proof-of-work, or the empty
  #   string as a placeholder
  #
  class BlockHeader
    include RLP::Sedes::Serializable

    extend Sedes

    set_serializable_fields(
      prevhash: hash32,
      uncles_hash: hash32,
      coinbase: address,
      state_root: trie_root,
      tx_list_root: trie_root,
      receipts_root: trie_root,
      bloom: int256,
      difficulty: big_endian_int,
      number: big_endian_int,
      gas_limit: big_endian_int,
      gas_used: big_endian_int,
      timestamp: big_endian_int,
      extra_data: binary,
      mixhash: binary,
      nonce: RLP::Sedes::Binary.new(min_length: 8, allow_empty: true) # FIXME: should be fixed length 8?
    )

    class <<self
      def from_block_rlp(rlp_data)
        block_data = RLP.decode_lazy rlp_data
        deserialize block_data[0]
      end
    end

    def initialize(options={})
      fields = {
        prevhash: Env::DEFAULT_CONFIG[:genesis_prevhash],
        uncles_hash: Utils.keccak_rlp([]),
        coinbase: Env::DEFAULT_CONFIG[:genesis_coinbase],
        state_root: PruningTrie::BLANK_ROOT,
        tx_list_root: PruningTrie::BLANK_ROOT,
        receipts_root: PruningTrie::BLANK_ROOT,
        bloom: 0,
        difficulty: Env::DEFAULT_CONFIG[:genesis_difficulty],
        number: 0,
        gas_limit: Env::DEFAULT_CONFIG[:genesis_gas_limit],
        gas_used: 0,
        timestamp: 0,
        extra_data: '',
        mixhash: Env::DEFAULT_CONFIG[:genesis_mixhash],
        nonce: ''
      }.merge(options)

      fields[:coinbase] = Utils.decode_hex(fields[:coinbase]) if fields[:coinbase].size == 40
      raise ArgumentError, "invalid coinbase #{coinbase}" unless fields[:coinbase].size == 20
      raise ArgumentError, "invalid difficulty" unless fields[:difficulty] > 0

      @block = nil
      @fimxe_hash = nil

      super(**fields)
    end

    def state_root
      get_with_block :state_root
    end

    def state_root=(v)
      set_with_block :state_root, v
    end

    def tx_list_root
      get_with_block :tx_list_root
    end

    def tx_list_root=(v)
      set_with_block :tx_list_root, v
    end

    def receipts_root
      get_with_block :receipts_root
    end

    def receipts_root=(v)
      set_with_block :receipts_root, v
    end

    def full_hash
      Utils.keccak_rlp self
    end

    def hex_full_hash
      Utils.encode_hex full_hash
    end

    def mining_hash
      Utils.keccak_256 RLP.encode(self, self.class.exclude(['mixhash', 'nonce']))
    end

    ##
    # Check if the proof-of-work of the block is valid.
    #
    # @param nonce [String] if given the proof of work function will be
    #   evaluated with this nonce instead of the one already present in the
    #   header
    #
    # @return [Bool]
    #
    def check_pow(nonce=nil)
      logger.debug "checking pow block=#{hex_full_hash[0,8]}"
      Miner.check_pow(number, mining_hash, mixhash, nonce || self.nonce, difficulty)
    end

    ##
    # Serialize the header to a readable hash.
    #
    def to_h
      h = {}

      %i(prevhash uncles_hash extra_data nonce mixhash).each do |field|
        h[field] = "0x#{Utils.encode_hex(send field)}"
      end

      %i(state_root tx_list_root receipts_root coinbase).each do |field|
        h[field] = Utils.encode_hex send(field)
      end

      %i(number difficulty gas_limit gas_used timestamp).each do |field|
        h[field] = send(field).to_s
      end

      h[:bloom] = Utils.encode_hex Sedes.int256.serialize(bloom)

      h
    end

    def to_s
      "#<#{self.class.name}:#{object_id} ##{number} #{hex_full_hash[0,8]}>"
    end
    alias :inspect :to_s

    ##
    # Two blockheader are equal iff they have the same hash.
    #
    def ==(other)
      other.instance_of?(BlockHeader) && full_hash == other.full_hash
    end
    alias :eql? :==

    def hash
      Utils.big_endian_to_int full_hash
    end

    private

    def logger
      Logger['eth.block']
    end

    def get_with_block(attr)
      @block ? @block.send(attr) : instance_variable_get(:"@#{attr}")
    end

    def set_with_block(attr, v)
      if @block
        @block.send :"#{attr}=", v
      else
        _set_field attr, v
      end
    end

  end
end
