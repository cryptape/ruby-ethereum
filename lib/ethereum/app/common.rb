# -*- encoding : ascii-8bit -*-

require 'devp2p'
require 'ethereum'

module Ethereum
  module App

    CLIENT_NAME = 'reth'
    CLIENT_VERSION = "#{VERSION}/#{RUBY_PLATFORM}/#{RUBY_ENGINE}-#{RUBY_VERSION}"
    CLIENT_VERSION_STRING = "#{CLIENT_NAME}/v#{CLIENT_VERSION}"

  end
end

