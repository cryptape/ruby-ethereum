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
#require 'ethereum/app/pow_service'

module Ethereum
  module App

    CLIENT_NAME = 'reth'
    CLIENT_VERSION = "#{VERSION}/#{RUBY_PLATFORM}/#{RUBY_ENGINE}-#{RUBY_VERSION}"
    CLIENT_VERSION_STRING = "#{CLIENT_NAME}-v#{CLIENT_VERSION}"

    class Full < ::DEVp2p::App

      default_config(
        client_version_string: CLIENT_VERSION_STRING,
        deactivated_services: [],
        post_app_start_callback: nil
      )

    end

  end
end
