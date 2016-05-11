# -*- encoding : ascii-8bit -*-

require 'devp2p'
require 'ethereum'

require 'ethereum/app/utils'
require 'ethereum/app/config'
require 'ethereum/app/profile'

require 'ethereum/app/keystore'
require 'ethereum/app/account'

require 'ethereum/app/duplicates_filter'
require 'ethereum/app/sync_task'
require 'ethereum/app/synchronizer'

require 'ethereum/app/transient_block'
require 'ethereum/app/eth_protocol'

require 'ethereum/app/account_service'
require 'ethereum/app/db_service'
require 'ethereum/app/chain_service'

module Ethereum
  module App

    CLIENT_NAME = 'reth'
    CLIENT_VERSION = "#{VERSION}/#{RUBY_PLATFORM}/#{RUBY_ENGINE}-#{RUBY_VERSION}"
    CLIENT_VERSION_STRING = "#{CLIENT_NAME}-v#{CLIENT_VERSION}"

    CANARY_ADDRESSES = [
      '539dd9aaf45c3feb03f9c004f4098bd3268fef6b',  # Gav
      'c8158da0b567a8cc898991c2c2a073af67dc03a9',  # Vitalik
      '959c33de5961820567930eccce51ea715c496f85',  # Jeff
      '7a19a893f91d5b6e2cdf941b6acbba2cbcf431ee'   # Christoph
    ].map {|hex| Utils.decode_hex(hex) }.freeze

  end
end

