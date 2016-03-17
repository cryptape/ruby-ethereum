# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester
    module Language

      class <<self
        def all
          return @all if @all

          @all = {
            serpent: Serpent,
            solidity: SolidityWrapper.solc_path && SolidityWrapper
          }

          @all
        end

        def get(name)
          all[name]
        end
      end

    end
  end
end
