# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester

    module SolidityWrapper

      class CompileError < StandardError; end

      class <<self
        def contract_names(code)
          code.scan(/^\s*(contract|library) (\S*) /m)
        end

        ##
        # compile combined-json with abi,bin,devdoc,userdoc
        #
        # @param code [String] literal solidity code
        # @param path [String] absolute path to solidity file. `code` and
        #   `path` are exclusive`
        #
        def combined(code, format: 'bin', path: nil)
          out = Tempfile.new 'solc_output_'

          pipe = nil
          if path
            raise ArgumentError, "code and path are exclusive" if code

            workdir = File.dirname path
            fn = File.basename path

            Dir.chdir(workdir) do
              pipe = IO.popen([solc_path, '--add-std', '--optimize', '--combined-json', "abi,#{format},devdoc,userdoc", fn], 'w', [:out, :err] => out)
              pipe.close_write
            end
          else
            pipe = IO.popen([solc_path, '--add-std', '--optimize', '--combined-json', "abi,#{format},devdoc,userdoc"], 'w', [:out, :err] => out)
            pipe.write code
            pipe.close_write
          end
          raise CompileError, 'compilation failed' unless $?.success?

          out.rewind
          contracts = JSON.parse(out.read)['contracts']

          contracts.each do |name, data|
            data['abi'] = JSON.parse data['abi']
            data['devdoc'] = JSON.parse data['devdoc']
            data['userdoc'] = JSON.parse data['userdoc']
          end

          names = contract_names(code || File.read(path))
          raise AssertError unless names.size <= contracts.size

          names.map {|n| [n[1], contracts[n[1]]] }
        ensure
          out.close
        end

        ##
        # Returns binary of last contract in code.
        #
        def compile(code, contract_name: '', format: 'bin', libraries: nil, path: nil)
          sorted_contracts = combined code, format: format, path: path
          if contract_name.true?
            idx = sorted_contracts.map(&:first).index(contract_name)
          else
            idx = -1
          end
          if libraries
            libraries.each do |name, address|
              raise CompileError, "Compiler does not support libraries. Please update Compiler." if compiler_version < '0.1.2'
              sorted_contracts[idx][1]['bin'].gsub! "__#{name}#{'_' * (38 - name.size)}", address
            end
          end

          output = sorted_contracts[idx][1][format]
          case format
          when 'bin'
            Utils.decode_hex output
          when 'asm'
            output['.code']
          when 'opcodes'
            output
          else
            raise ArgumentError
          end
        end

        ##
        # Returns signature of last contract in code.
        #
        def mk_full_signature(code, contract_name: '', libraries: nil, path: nil)
          sorted_contracts = combined code, path: path
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
        def compile_rich(code, path: nil)
          combined(code, path: path).map do |(name, contract)|
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
