# -*- encoding : ascii-8bit -*-

require 'serpent'

##
# Helper methods for managing ECDSA-based accounts on top of Serenity.
#
module Ethereum
  module ECDSAAccount

    MAGIC = "\x82\xa9x\xb3\xf5\x96*[\tW\xd9\xee\x9e\xefG.\xe5[B\xf1".freeze

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

      def mandatory_account_source
        return @mandatory_account_source if @mandatory_account_source

        source = File.binread contract_path('mandatory_account_code')
        @mandatory_account_source = source % [
          Utils.big_endian_to_int(Config::NULL_SENDER),
          Utils.big_endian_to_int(Config::GAS_DEPOSIT),
          Utils.big_endian_to_int(Config::GAS_DEPOSIT)
        ]
      end

      def mandatory_account_code
        return @mandatory_account_code if @mandatory_account_code

        code = Serpent.compile mandatory_account_source
        # Strip off the initiation wrapper # FIXME: too hacky
        code = code[(code.index("\x56")+1)..-1]
        code = code[0,code[0...-1].rindex("\xf3")+1]

        @mandatory_account_code = code
      end

      def mandatory_account
        @mandatory_account ||= ABI::ContractTranslator.new Serpent.mk_full_signature(mandatory_account_source)
      end

      ##
      # The init code for an ECDSA account. Calls the constructor storage
      # contract to get the ECDSA account code, then uses mcopy to swap the
      # default address for the user's pubkeyhash.
      #
      def account_code
        return @account_code if @account_code

        source = File.binread contract_path('account_code')
        source = source % [
          Utils.big_endian_to_int(Config::ECRECOVERACCT),
          Utils.big_endian_to_int(Config::BASICSENDER)
        ]
        source = "#{source}\n#{mandatory_account_source}"

        @account_code = Serpent.compile source
      end

      def privtoaddr(k, left_bound: 0)
        pubkeyhash = Utils.priv_to_pubhash k
        Utils.mk_contract_address code: mk_account_code(pubkeyhash), left_bound: left_bound
      end

      def mk_account_code(pubkeyhash)
        account_code.sub MAGIC, pubkeyhash
      end

      def validation_code
        @validation_source ||= Serpent.compile contract_path('validation')
      end

      ##
      # Make the validation code for a particular address.
      #
      def mk_validation_code(k)
        pubkeyhash = Utils.priv_to_pubhash k

        code = validation_code.sub MAGIC, pubkeyhash

        s = State.new Trie::BLANK_NODE, DB::EphemDB.new
        s.set_gas_limit 10**9
        s.tx_state_transition Transaction.new(nil, 1000000, data: Constant::BYTE_EMPTY, code: code)

        s.get_code Utils.mk_contract_address(code: code)
      end

      ##
      # The equivalent of `Transaction.new(nonce, gasprice, startgas, to, value,
      # data).sign(key)` in 1.0
      #
      def mk_transaction(seq, gasprice, gas, to, value, data, key, create: false)
        code = create ? mk_account_code(Utils.priv_to_pubhash(key)) : Constant::BYTE_EMPTY

        addr = Utils.mk_contract_address code: code
        data = sign_txdata mk_txdata(seq, gasprice, to, value, data), gas, key

        Transaction.new(addr, gas, data: data, code: code)
      end

      def mk_txdata(seq, gasprice, to, value, data)
        to = Utils.zpad Utils.normalize_address(to), 32
        "#{Utils.zpad_int(gasprice)}#{Utils.zpad_int(seq)}#{to}#{Utils.zpad_int(value)}#{data}"
      end

      def sign_txdata(data, gas, key)
        v, r, s = Secp256k1.ecdsa_raw_sign Utils.keccak256(Utils.zpad_int(gas)+data), key
        "#{Utils.zpad_int(v)}#{Utils.zpad_int(r)}#{Utils.zpad_int(s)}#{data}"
      end

    end

  end
end
