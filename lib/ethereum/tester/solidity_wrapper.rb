# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester

    module SolidityWrapper

      class CompileError < StandardError; end

      class <<self

        def compile_code_or_path(code, path, contract_name, libraries, combined)
          raise ValueError, 'code and path are mutually exclusive' if code && path

          return compile_contract(path, contract_name, libraries: libraries, combined: combined) if path && contract_name.true?
          return compile_last_contract(path, libraries: libraries, combined: combined) if path

          all_names = solidity_names code
          all_contract_names = all_names
            .select {|(kind, name)| kind == 'contract' }
            .map(&:last)

          result = compile_code(code, libraries: libraries, combined: combined)
          result[all_contract_names.last]
        end

        ##
        # Returns binary of last contract in code.
        #
        def compile(code, contract_name: '', libraries: nil, path: nil)
          result = compile_code_or_path code, path, contract_name, libraries, 'bin'
          result['bin']
        end

        ##
        # Returns signature of last contract in code.
        #
        def mk_full_signature(code, contract_name: '', libraries: nil, path: nil)
          result = compile_code_or_path code, path, contract_name, libraries, 'abi'
          result['abi']
        end

        ##
        # Compile combined-json with abi,bin,devdoc,userdoc.
        #
        def combined(code, path: nil)
          contracts = compile_code_or_path code, path, nil, nil, 'abi,bin,devdoc,userdoc'
          code = File.read(path) if path
          solidity_names(code).map do |(kind, name)|
            [name, contracts[name]]
          end
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

        def compile_code(code, libraries: nil, combined:'bin,abi', optimize: true)
          args = solc_arguments libraries: libraries, combined: combined, optimize: optimize
          args.unshift solc_path

          out = Tempfile.new 'solc_output_'
          pipe = IO.popen(args, 'w', [:out, :err] => out)
          pipe.write code
          pipe.close_write
          raise CompileError, 'compilation failed' unless $?.success?

          out.rewind
          solc_parse_output out.read
        end

        def compile_last_contract(path, libraries: nil, combined: 'bin,abi', optimize: true)
          all_names = solidity_names File.read(path)
          all_contract_names = all_names.map(&:last) # don't filter libraries
          compile_contract path, all_contract_names.last, libraries: libraries, combined: combined, optimize: optimize
        end

        def compile_contract(path, contract_name, libraries: nil, combined: 'bin,abi', optimize: true)
          all_contracts = compile_file path, libraries: libraries, combined: combined, optimize: optimize
          all_contracts[contract_name]
        end

        ##
        # Return the compiled contract code.
        #
        # @param path [String] Path to the contract source code.
        # @param libraries [Hash] A hash mapping library name to address.
        # @param combined [Array[String]] The flags passed to the solidity
        #   compiler to define what output should be used.
        # @param optimize [Bool] Flag to set up compiler optimization.
        #
        # @return [Hash] A mapping from the contract name to it's bytecode.
        #
        def compile_file(path, libraries: nil, combined: 'bin,abi', optimize: true)
          workdir = File.dirname path
          filename = File.basename path

          args = solc_arguments libraries: libraries, combined: combined, optimize: optimize
          args.unshift solc_path
          args.push filename

          out = Tempfile.new 'solc_output_'
          Dir.chdir(workdir) do
            pipe = IO.popen(args, 'w', [:out, :err] => out)
            pipe.close_write
          end

          out.rewind
          solc_parse_output out.read
        end

        ##
        # Return the library and contract names in order of appearence.
        #
        def solidity_names(code)
          code.scan /(contract|library)\s+([_a-zA-Z][_a-zA-Z0-9]*)/m
        end

        def compiler_version
          output = `#{solc_path} --version`.strip
          output =~ /^Version: ([0-9a-z.-]+)\///m ? $1 : nil
        end

        ##
        # Parse compiler output.
        #
        def solc_parse_output(compiler_output)
          result = JSON.parse(compiler_output)['contracts']

          if result.values.first.has_key?('bin')
            result.each_value do |v|
              v['bin_hex'] = v['bin']
              v['bin'] = Utils.decode_hex v['bin']
            end
          end

          %w(abi devdoc userdoc).each do |json_data|
            next unless result.values.first.has_key?(json_data)

            result.each_value do |v|
              v[json_data] = JSON.parse v[json_data]
            end
          end

          result
        end

        def solc_arguments(libraries: nil, combined: 'bin,abi', optimize: true)
          args = [
            '--combined-json', combined,
            '--add-std'
          ]

          args.push '--optimize' if optimize

          if libraries
            addresses = libraries.map {|name, addr| "#{name}:#{addr}" }
            args.push '--libraries'
            args.push addresses.join(',')
          end

          args
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
