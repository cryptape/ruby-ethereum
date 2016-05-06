# -*- encoding : ascii-8bit -*-

require 'ethereum/app/common'

module Ethereum
  module App

    class Full < ::DEVp2p::BaseApp

      default_config(
        client_version_string: CLIENT_VERSION_STRING,
        deactivated_services: [],
        post_app_start_callback: nil
      )

    end

  end
end
