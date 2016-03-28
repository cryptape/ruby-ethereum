# -*- encoding : ascii-8bit -*-

module Ethereum
  module Constant

    BYTE_EMPTY = "".freeze
    BYTE_ZERO = "\x00".freeze
    BYTE_ONE  = "\x01".freeze

    TT32  = 2**32
    TT256 = 2**256
    TT64M1 = 2**64 - 1

    UINT_MAX = 2**256 - 1
    UINT_MIN = 0
    INT_MAX = 2**255 - 1
    INT_MIN = -2**255

    HASH_ZERO = ("\x00"*32).freeze

    PUBKEY_ZERO = [0,0].freeze
    PRIVKEY_ZERO = ("\x00"*32).freeze

    def self.int_to_addr(x)
      Utils.int_to_addr x
    end

    ##
    # System Addresses
    #

    STATEROOTS = int_to_addr 20
    BLKNUMBER = int_to_addr 30
    ETHER = int_to_addr 50
    CASPER = int_to_addr 60
    ECRECOVERACCT = int_to_addr 70
    PROPOSER = int_to_addr 80
    RNGSEEDS = int_to_addr 90
    BLOCKHASHES = int_to_addr 100
    GENESIS_TIME = int_to_addr 110
    LOG = int_to_addr 120
    BET_INCENTIVIZER = int_to_addr 150
    EXECUTION_STATE = int_to_addr 160
    CREATOR = int_to_addr 170
    GAS_DEPOSIT = int_to_addr 180
    BASICSENDER = int_to_addr 190
    SYS = int_to_addr 200
    TX_ENTRY_POINT = int_to_addr(2**160 - 1)

    ##
    # Global Parameters
    #

    BLKTIME = 3.75
    TXGAS = 1
    TXINDEX = 2
    GAS_REMAINING = 3
    BLOOM = 2**32
    GASLIMIT = 4712388 # Pau million

    NULL_SENDER = int_to_addr 0
    CONST_CALL_SENDER = int_to_addr 31415

    ENTRY_EXIT_DELAY = 110 # must be set in Casper contract as well
    VALIDATOR_ROUNDS = 5 # must be set in Casper contract as well

    MAXSHARDS = 65536
    SHARD_BYTES = Utils.int_to_big_endian(MAXSHARDS-1).size
    ADDR_BASE_BYTES = 20
    ADDR_BYTES = ADDR_BASE_BYTES + SHARD_BYTES

    UNHASH_MAGIC_BYTES = "unhash:"

  end
end
