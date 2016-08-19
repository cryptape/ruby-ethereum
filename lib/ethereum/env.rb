# -*- encoding : ascii-8bit -*-

module Ethereum
  class Env

    DEFAULT_CONFIG = {
      # Genesis constants
      genesis_difficulty: 131072,
      genesis_gas_limit: 3141592,
      genesis_prevhash: Constant::HASH_ZERO,
      genesis_coinbase: Address::ZERO,
      genesis_nonce: Utils.zpad_int(42, 8),
      genesis_mixhash: Constant::HASH_ZERO,
      genesis_timestamp: 0,
      genesis_extra_data: Constant::BYTE_EMPTY,
      genesis_initial_alloc: {},

      # Gas limit adjustment algo:
      #
      # block.gas_limit = block.parent.gas_limit * 1023/1024 +
      #                     (block.gas.used * 6/5) / 1024
      min_gas_limit: 5000,
      gaslimit_ema_factor: 1024,
      gaslimit_adjmax_factor: 1024,
      blklim_factor_nom: 3,
      blklim_factor_den: 2,

      block_reward:  5000.finney,
      nephew_reward: 5000.finney/32, # block_reward/32

      # GHOST constants
      uncle_depth_penalty_factor: 8,
      max_uncle_depth: 6, # max (block.number - uncle.number)
      max_uncles: 2,

      diff_adjustment_cutoff: 13,
      block_diff_factor: 2048,
      min_diff: 131072,

      pow_epoch_length: 30000,

      max_extradata_length: 32,

      expdiff_period: 100000,
      expdiff_free_periods: 2,

      account_initial_nonce: 0,

      # Milestones
      homestead_fork_blknum: 1150000,
      homestead_diff_adjustment_cutoff: 10,

      metropolis_fork_blknum: 2**100,
      metropolis_entry_point: 2**160-1,
      metropolis_stateroot_store: 0x10,
      metropolis_blockhash_store: 0x20,
      metropolis_wrapround: 65536,
      metropolis_getter_code: Utils.decode_hex('6000355460205260206020f3'),
      metropolis_diff_adjustment_cutoff: 9,

      dao_fork_blknum: 9999998,
      dao_address_list: [],
      dao_main_addr: '0xbb9bc244d798123fde783fcc1c72d3bb8c189413',
      dao_newcode: ''
    }.freeze

    attr :db, :config, :global_config

    def initialize(db, config: nil, global_config: {})
      @db = db
      @config = config || DEFAULT_CONFIG
      @global_config = global_config

      raise "invalid nephew/block reward config" unless @config[:nephew_reward] == @config[:block_reward]/32
    end

  end
end
