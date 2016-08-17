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
          all_contract_names = all_names.map(&:last)

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
          raise ValueError, "code and path are mutually exclusive." if code && path

          if path
            contracts = compile_file path
            code = File.read(path)
          elsif code
            contracts = compile_code code
          else
            raise ValueError, 'either code or path needs to be supplied.'
          end

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
                'code' => "0x#{contract['bin_hex']}",
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
        # @param libraries [Hash] A hash mapping library name to its address.
        # @param combined [Array[String]] The argument for solc's --combined-json.
        # @param optimize [Bool] Enable/disables compiler optimization.
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
          names = []
          in_string = nil
          backslash = false
          comment = nil

          # "parse" the code by hand to handle the corner cases:
          #
          # - the contract or library can be inside a comment or string
          # - multiline comments
          # - the contract and library keywords could not be at the start of the line
          code.each_char.with_index do |char, pos|
            if in_string
              if !backslash && in_string == char
                in_string = nil
                backslash = false
              end

              backslash = char == "\\"
            elsif comment == "//"
              comment = nil if ["\n", "\r"].include?(char)
            elsif comment == "/*"
              comment = nil if char == "*" && code[pos + 1] == "/"
            else
              in_string = char if %w(' ").include?(char)

              if char == "/"
                char2 = code[pos + 1]
                comment = char + char2 if %w(/ *).include?(char2)
              end

              if char == 'c' && code[pos, 8] == 'contract'
                result = code[pos..-1] =~ /^contract[^_$a-zA-Z]+([_$a-zA-Z][_$a-zA-Z0-9]*)/
                names.push ['contract', $1] if result
              end

              if char == 'l' && code[pos, 7] == 'library'
                result = code[pos..-1] =~ /^library[^_$a-zA-Z]+([_$a-zA-Z][_$a-zA-Z0-9]*)/
                names.push ['library', $1] if result
              end
            end
          end

          names
        end

        ##
        # Return the symbol used in the bytecode to represent the
        # `library_name`.
        #
        # The symbol is always 40 characters in length with the minimum of two
        # leading and trailing underscores.
        #
        def solidity_library_symbol(library_name)
          len = [library_name.size, 36].min
          lib_piece = library_name[0,len]
          hold_piece = '_' * (36 - len)
          "__#{lib_piece}#{hold_piece}__"
        end

        ##
        # Change the bytecode to use the given library address.
        #
        # @param hex_code [String] The bytecode encoded in hex.
        # @param library_name [String] The library that will be resolved.
        # @param library_address [String] The address of the library.
        #
        # @return [String] The bytecode encoded in hex with the library
        #   references.
        #
        def solidity_resolve_address(hex_code, library_symbol, library_address)
          raise ValueError, "Address should not contain the 0x prefix" if library_address =~ /\A0x/
          raise ValueError, "Address with wrong length" if library_symbol.size != 40 || library_address.size != 40

          begin
            Utils.decode_hex library_address
          rescue TypeError
            raise ValueError, "library_address contains invalid characters, it must be hex encoded."
          end

          hex_code.gsub library_symbol, library_address
        end

        def solidity_resolve_symbols(hex_code, libraries)
          symbol_address = libraries
            .map {|name, addr| [solidity_library_symbol(name), addr] }
            .to_h

          solidity_unresolved_symbols(hex_code).each do |unresolved|
            address = symbol_address[unresolved]
            hex_code = solidity_resolve_address(hex_code, unresolved, address)
          end

          hex_code
        end

        ##
        # Return the unresolved symbols contained in the `hex_code`.
        #
        # Note: the binary representation should not be provided since this
        # function relies on the fact that the '_' is invalid in hex encoding.
        #
        # @param hex_code [String] The bytecode encoded as hex.
        #
        def solidity_unresolved_symbols(hex_code)
          hex_code.scan(/_.{39}/).uniq
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

              # decoding can fail if the compiled contract has unresolved symbols
              begin
                v['bin'] = Utils.decode_hex v['bin']
              rescue TypeError
                # do nothing
              end
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

          if libraries && !libraries.empty?
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
