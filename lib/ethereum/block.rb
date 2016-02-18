require 'forwardable'

module Ethereum

  ##
  # A block.
  #
  # All attributes from the block header are accessible via properties (i.e.
  # `block.prevhash` is equivalent to `block.header.prevhash`). It is ensured
  # that no discrepancies between header and the block occur.
  #
  class Block
    include RLP::Sedes::Serializable

    HeaderGetters = (BlockHeader.serializable_fields.keys - %i(state_root receipts_root tx_list_root)).freeze
    HeaderSetters = HeaderGetters.map {|field| :"#{field}=" }.freeze

    extend Forwardable
    def_delegators :header, *HeaderGetters, *HeaderSetters

    class ValidationError < StandardError; end

    set_serializable_fields(
      header: BlockHeader,
      uncles: RLP::Sedes::CountableList.new(BlockHeader),
      transaction_list: RLP::Sedes::CountableList.new(Transaction)
    )

    attr :db, :config

    ##
    # @param header [BlockHeader] the block header
    # @param transaction_list [Array[Transaction]] a list of transactions which
    #   are replayed if the state given by the header is not known. If the state
    #   is known, `nil` can be used instead of the empty list.
    # @param unlces [Array[BlockHeader]] a list of the headers of the uncles of
    #   this block
    # @param env [Env] env including db in which the block's state,
    #   transactions and receipts are stored (required)
    # @param parent [Block] optional parent which if not given may have to be
    #   loaded from the database for replay
    def initialize(header, transaction_list: [], uncles: [], env: nil, parent: nil, making: false)
      raise ArgumentError, "No Env object given" unless env.instance_of?(Env)
      raise ArgumentError, "No database object given" unless env.db.is_a?(DB::BaseDB)

      @env = env
      @db = env.db
      @config = env.config

      @header = header
      @uncles = uncles

      @suicides = []
      @logs = []
      @log_listeners = []

      @refunds = 0
      @ether_delta = 0

      @get_transactions_cache = []

      # Journaling cache for state tree updates
      @caches = {
        balance: {},
        nonce: {},
        code: {},
        storage: {},
        all: {}
      }
      @journal = []

      @ancestor_hashes = number > 0 ? [prevhash] : [nil]*256

      validate_parent!(parent) if parent

      original_values = {
        gas_used: header.gas_used,
        timestamp: header.timestamp,
        difficulty: header.difficulty,
        uncles_hash: header.uncles_hash,
        bloom: header.bloom,
        header_mutable: header.mutable?
      }

      @_mutable = true
      header.instance_variable_set :@_mutable, true

      @transactions = Trie.new @db
      @receipts = Trie.new @db

      initialize_state

      # TODO: more
    end

    private

    def initialize_state
      # TODO
    end

    def validate_parent!(parent)
      raise ValidationError, "Parent lives in different database" if parent && db != parent.db && db.db != parent.db # TODO: refactor the db.db mess
      raise ValidationError, "Block's prevhash and parent's hash do not match" if prevhash != parent.header.full_hash
      raise ValidationError, "Block's number is not the successor of its parent number" if number != parent.number+1
      raise ValidationError, "Block's gaslimit is inconsistent with its parent's gaslimit" unless valid_gas_limit?(parent, gas_limit)
      raise ValidationError, "Block's difficulty is inconsistent with its parent's difficulty" if difficulty != calc_difficulty(parent, timestamp)
      raise ValidationError, "Gas used exceeds gas limit" if gas_used > gas_limit
      raise ValidationError, "Timestamp equal to or before parent" if timestamp <= parent.timestamp
      raise ValidationError, "Timestamp way too large" if timestamp > Constant::UINT_MAX
    end

    def valid_gas_limit?(parent, gl)
      adjmax = parent.gas_limit / parent.config[:gaslimit_adjmax_factor]
      (gl - parent.gas_limit).abs <= adjmax && gl >= parent.config[:min_gas_limit]
    end

    def calc_difficulty(parent, ts)
      # TODO
    end
  end
end
