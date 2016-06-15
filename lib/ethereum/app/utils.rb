# -*- encoding : ascii-8bit -*-

require 'securerandom'

module Ethereum
  module App

    module Utils

      include ::Ethereum::Utils
      extend self

      def mk_random_privkey
        SecureRandom.random_bytes(32)
      end

      def mk_privkey(seed)
        keccak256 seed
      end

    end

  end
end
