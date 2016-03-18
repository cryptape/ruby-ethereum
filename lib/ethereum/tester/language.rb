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

        def format_spaces(code)
          code =~ /\A(\s+)/ ? code.gsub(/^#{$1}/, '') : code
        end
      end

    end
  end
end
