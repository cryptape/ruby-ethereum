#!/usr/bin/env ruby

$:.unshift File.expand_path('../../lib', __FILE__)

require 'ethereum'
require 'ethereum/serenity'

include Ethereum

MAX_NODES = 12

CLOCKWRONG = 0
CLOCKWRONG_CUMUL = CLOCKWRONG + 1

BRAVE = 0
BRAVE_CUMUL = CLOCKWRONG_CUMUL + BRAVE

CRAZYBET = 0
CRAZYBET_CUMUL = BRAVE_CUMUL + CRAZYBET

DBL_BLK_SUICIDE = 0
DBL_BLK_SUICIDE_CUMUL = CRAZYBET_CUMUL + DBL_BLK_SUICIDE

DBL_BET_SUICIDE = 0
DBL_BET_SUICIDE_CUMUL = DBL_BLK_SUICIDE_CUMUL + DBL_BET_SUICIDE

raise AssertError, "Negative Numbers or too many nodes with special properties" unless
  0 <= CLOCKWRONG_CUMUL && CLOCKWRONG_CUMUL <= BRAVE_CUMUL && BRAVE_CUMUL <= CRAZYBET_CUMUL &&
    CRAZYBET_CUMUL <= DBL_BLK_SUICIDE_CUMUL && DBL_BLK_SUICIDE_CUMUL <= DBL_BET_SUICIDE_CUMUL &&
    DBL_BET_SUICIDE_CUMUL <= MAX_NODES

puts "Running with #{MAX_NODES} maximum nodes: #{CLOCKWRONG} with wonky clocks, #{BRAVE} brave, #{CRAZYBET} crazy-betting, #{DBL_BLK_SUICIDE} double-block suiciding, #{DBL_BET_SUICIDE} double-bet suiciding"

genesis = State.new Trie::BLANK_NODE, DB::EphemDB.new
genesis.set_gas_limit 10**9
gc = genesis.clone

