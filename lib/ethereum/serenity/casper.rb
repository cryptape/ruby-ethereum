# -*- encoding : ascii-8bit -*-

module Ethereum
  class Casper

    class <<self
      def gvi_cache
        @gvi_cache ||= {}
      end

      def get_guardian_index(state, blknum)
        unless gvi_cache.has_key?(blknum)
          n = blknum >= Constant::ENTER_EXIT_DELAY ? blknum - Constant::ENTER_EXIT_DELAY : 2**256-1
          preseed = state.get_storage Config::RNGSEEDS, n
          gvi_cache[blknum] = state.call_casper 'sampleGuardian', [preseed, blknum], gas: 3000000
        end

        gvi_cache[blknum]
      end

      def file
        @file ||= File.expand_path('../casper.se.py', __FILE__)
      end

      def abi_file
        @abi_file ||= File.expand_path('../_casper.abi', __FILE__)
      end

      def hash_file
        @hash_file ||= File.expand_path('../_casper.hash', __FILE__)
      end

      def evm_file
        @evm_file ||= File.expand_path('../_casper.evm', __FILE__)
      end

      def code
        return @code if @code
        init
        @code
      end

      def abi
        return @abi if @abi
        init
        @abi
      end

      def contract
        @contract ||= ABI::ContractTranslator.new abi
      end

      def init
        h = Utils.encode_hex Utils.keccak256(File.binread(file))
        raise AssertError, "casper contract hash mismatch" unless h == File.binread(hash_file)
        @code = File.binread(evm_file)
        @abi = JSON.parse File.binread(abi_file)
      rescue
        puts "Compiling casper contract ..."
        h = Utils.encode_hex Utils.keccak256(File.binread(file))
        @code = Serpent.compile file
        @abi = Serpent.mk_full_signature file

        File.open(abi_file, 'w') {|f| f.write JSON.dump(@abi) }
        File.open(evm_file, 'w') {|f| f.write @code }
        File.open(hash_file, 'w') {|f| f.write h }
      end
    end

  end
end
