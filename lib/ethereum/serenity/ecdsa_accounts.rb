# -*- encoding : ascii-8bit -*-

require 'serpent'

##
# Helper methods for managing ECDSA-based accounts on top of Serenity.
#
module Ethereum
  module ECDSAAccount

    class <<self
      def contract_path(name)
        File.expand_path "../ecdsa_accounts/#{name}.se.py", __FILE__
      end

      def constructor_code
        @constructor_code ||= Serpent.compile contract_path('constructor')
      end

      def constructor
        @constructor ||= ABI::ContractTranslator.new Serpent.mk_full_signature(contract_path('constructor'))
      end

      def runner_code
        @runner_code ||= Serpent.compile contract_path('runner')
      end

      def runner
        @runner ||= ABI::ContractTranslator.new Serpent.mk_full_signature(contract_path('runner'))
      end
    end

  end
end
