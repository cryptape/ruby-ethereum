# -*- encoding : ascii-8bit -*-

module Ethereum
  module Config

    def self.int_to_addr(x)
      Utils.int_to_addr x
    end

    NULL_SENDER = int_to_addr 0
    CONST_CALL_SENDER = int_to_addr 31415

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

  end
end
