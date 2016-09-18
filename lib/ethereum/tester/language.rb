# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester
    module Language

      class <<self
        def all
          return @all if @all

          @all = {}

          begin
            require 'serpent'
            @all[:serpent] = Serpent
          rescue LoadError => e
            puts "Failed to load serpent"
          end

          if SolidityWrapper.solc_path
            @all[:solidity] = SolidityWrapper
          end

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
