# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester

    module SolidityWrapper

      class CompileError < StandardError; end

      class <<self
        def split_contracts(code)
          contracts = []
          contract = nil

          code.split("\n").each do |line|
            if line =~ /\Acontract /
              contracts.push(contract.join("\n")) if contract
              contract = [line]
            elsif contract
              contract.push line
            end
          end

          contracts.push(contract.join("\n")) if contract

          contracts
        end

        def contract_names(code)
          names = []

          split_contracts(code).each do |contract|
            keyword, name, _ = contract.split(/\s+/, 3)
            raise AssertError, 'keyword must be contract' unless keyword == 'contract' && !name.empty?
            names.push name
          end

          names
        end

        def combined(code)
          out = Tempfile.new 'solc_output_'

          pipe = IO.popen([solc_path, '--add-std', '--optimize', '--combined-json', 'abi,bin,devdoc,userdoc'], 'w', [:out, :err] => out)
          pipe.write code
          pipe.close_write
          raise CompileError, 'compilation failed' unless $?.success?

          out.rewind
          contracts = JSON.parse(out.read)['contracts']

          contracts.each do |name, data|
            data['abi'] = JSON.parse data['abi']
            data['devdoc'] = JSON.parse data['devdoc']
            data['userdoc'] = JSON.parse data['userdoc']
          end

          names = contract_names code
          raise AssertError unless names.size <= contracts.size

          names.map {|n| [n, contracts[n]] }
        ensure
          out.close
        end

        ##
        # Returns binary of last contract in code.
        #
        def compile(code, contract_name='')
          sorted_contracts = combined code
          if contract_name.true?
            idx = sorted_contracts.map(&:first).index(contract_name)
          else
            idx = -1
          end

          Utils.decode_hex sorted_contracts[idx][1]['bin']
        end

        ##
        # Returns signature of last contract in code.
        #
        def mk_full_signature(code, contract_name='')
          sorted_contracts = combined code
          if contract_name.true?
            idx = sorted_contracts.map(&:first).index(contract_name)
          else
            idx = -1
          end

          sorted_contracts[idx][1]['abi']
        end

        def compiler_version
          output = `#{solc_path} --version`.strip
          output =~ /^Version: ([0-9a-z.-]+)\// ? $1 : nil
        end

        ##
        # Full format as returned by jsonrpc.
        #
        def compile_rich(code)
          combined(code).map do |(name, contract)|
            [
              name,
              {
                'code' => "0x#{contract['bin']}",
                'info' => {
                  'abiDefinition' => contract['abi'],
                  'compilerVersion' => compiler_version,
                  'developerDoc' => contract['devdoc'],
                  'language' => 'Solidity',
                  'languageVersion' => '0',
                  'source' => code,
                  'userDoc' => contract['userdoc']
                }
              }
            ]
          end.to_h
        end

        def solc_path
          @solc_path ||= which('solc')
        end

        def solc_path=(v)
          @solc_path = v
        end

        def which(cmd)
          exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
          ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
            exts.each { |ext|
              exe = File.join(path, "#{cmd}#{ext}")
              return exe if File.executable?(exe) && !File.directory?(exe)
            }
          end
          return nil
        end
      end
    end

  end
end
