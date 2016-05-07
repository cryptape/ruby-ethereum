# -*- encoding : ascii-8bit -*-

require 'devp2p'
require 'ethereum'

require 'ethereum/app/utils'
require 'ethereum/app/config'

require 'ethereum/app/keystore'
require 'ethereum/app/account'

require 'ethereum/app/account_service'
require 'ethereum/app/db_service'

module Ethereum
  module App

    CLIENT_NAME = 'reth'
    CLIENT_VERSION = "#{VERSION}/#{RUBY_PLATFORM}/#{RUBY_ENGINE}-#{RUBY_VERSION}"
    CLIENT_VERSION_STRING = "#{CLIENT_NAME}-v#{CLIENT_VERSION}"

  end
end

