# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester
    module Fixture

      NUM_ACCOUNTS = 10

      GAS_PRICE = 1
      GAS_LIMIT = 3141592

      class <<self
        def keys
          @keys ||= NUM_ACCOUNTS.times.map {|i| Utils.keccak256(i.to_s) }
        end

        def accounts
          @accounts ||= NUM_ACCOUNTS.times.map {|i| PrivateKey.new(keys[i]).to_address }
        end

        def int_to_addr(x)
          Utils.zpad_int(x, 20)
        end
      end

    end
  end
end
