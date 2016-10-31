# -*- encoding : ascii-8bit -*-

require 'json'

module Ethereum
  module ABI
    class ContractTranslator

      def initialize(contract_interface)
        if contract_interface.instance_of?(String)
          contract_interface = JSON.parse contract_interface
        end

        @contract = {
          fallback_data: nil,
          constructor_data: nil,
          function_data: {},
          event_data: {}
        }

        contract_interface.each do |desc|
          type = desc['type'] || 'function'
          encode_types = []
          signature = []

          if type != 'fallback' && desc.has_key?('inputs')
            encode_types = desc['inputs'].map {|e| e['type'] }
            signature = desc['inputs'].map {|e| [e['type'], e['name']] }
          end

          case type
          when 'function'
            name = basename desc['name']
            decode_types = desc['outputs'].map {|e| e['type'] }
            @contract[:function_data][name] = {
              prefix: method_id(name, encode_types),
              encode_types: encode_types,
              decode_types: decode_types,
              is_constant: desc.fetch('constant', false),
              signature: signature,
              payable: desc.fetch('payable', false)
            }
          when 'event'
            name = basename desc['name']
            indexed = desc['inputs'].map {|e| e['indexed'] }
            names = desc['inputs'].map {|e| e['name'] }
            @contract[:event_data][event_id(name, encode_types)] = {
              types: encode_types,
              name: name,
              names: names,
              indexed: indexed,
              anonymous: desc.fetch('anonymous', false)
            }
          when 'constructor'
            raise ValueError, "Only one constructor is supported." if @contract[:constructor_data]
            @contract[:constructor_data] = {
              encode_types: encode_types,
              signature: signature
            }
          when 'fallback'
            raise ValueError, "Only one fallback function is supported." if @contract[:fallback_data]
            @contract[:fallback_data] = {
              payable: desc['payable']
            }
          else
            raise ValueError, "Unknown interface type: #{type}"
          end
        end
      end

      ##
      # Return the encoded function call.
      #
      # @param name [String] One of the existing functions described in the
      #   contract interface.
      # @param args [Array[Object]] The function arguments that will be encoded
      #   and used in the contract execution in the vm.
      #
      # @return [String] The encoded function name and arguments so that it can
      #   be used with the evm to execute a function call, the binary string
      #   follows the Ethereum Contract ABI.
      #
      def encode(name, args)
        raise ValueError, "Unknown function #{name}" unless function_data.include?(name)

        desc = function_data[name]
        func_id = Utils.zpad(Utils.encode_int(desc[:prefix]), 4)
        calldata = ABI.encode_abi desc[:encode_types], args

        "#{func_id}#{calldata}"
      end

      ##
      # Return the encoded constructor call.
      #
      def encode_constructor_arguments(args)
        raise ValueError, "The contract interface didn't have a constructor" unless constructor_data

        ABI.encode_abi constructor_data[:encode_types], args
      end

      ##
      # Return the function call result decoded.
      #
      # @param name [String] One of the existing functions described in the
      #   contract interface.
      # @param data [String] The encoded result from calling function `name`.
      #
      # @return [Array[Object]] The values returned by the call to function
      #
      def decode_function_result(name, data)
        desc = function_data[name]
        ABI.decode_abi desc[:decode_types], data
      end
      alias :decode :decode_function_result

      ##
      # Return a dictionary represent the log.
      #
      # Notes: this function won't work with anonymous events.
      #
      # @param log_topics [Array[String]] The log's indexed arguments.
      # @param log_data [String] The encoded non-indexed arguments.
      #
      def decode_event(log_topics, log_data)
        # topics[0]: keccak256(normalized_event_name)
        raise ValueError, "Unknown log type" unless log_topics.size > 0 && event_data.has_key?(log_topics[0])

        event_id = log_topics[0]
        event = event_data[event_id]

        names = event[:names]
        types = event[:types]
        indexed = event[:indexed]

        unindexed_types = types.zip(indexed).select {|(t, i)| i.false? }.map(&:first)
        unindexed_args = ABI.decode_abi unindexed_types, log_data

        result = {}
        indexed_count = 1 # skip topics[0]
        names.each_with_index do |name, i|
          v = if indexed[i].true?
                topic_bytes = Utils.zpad_int log_topics[indexed_count]
                indexed_count += 1
                ABI.decode_primitive_type ABI::Type.parse(types[i]), topic_bytes
              else
                unindexed_args.shift
              end

          result[name] = v
        end

        result['_event_type'] = event[:name]
        result
      end

      ##.
      # Return a dictionary representation of the Log instance.
      #
      # Note: this function won't work with anonymous events.
      #
      # @param log [Log] The Log instance that needs to be parsed.
      # @param noprint [Bool] Flag to turn off printing of the decoded log
      #   instance.
      #
      def listen(log, noprint: true)
        result = decode_event log.topics, log.data
        p result if noprint
        result['_from'] = Utils.encode_hex(log.address)
        result
      rescue ValueError
        nil # api compatibility
      end

      def constructor_data
        @contract[:constructor_data]
      end

      def function_data
        @contract[:function_data]
      end

      def event_data
        @contract[:event_data]
      end

      def function(name)
        function_data[name]
      end

      def event(name, encode_types)
        event_data[event_id(name, encode_types)]
      end

      def method_id(name, encode_types)
        Utils.big_endian_to_int Utils.keccak256(get_sig(name, encode_types))[0,4]
      end

      def event_id(name, encode_types)
        Utils.big_endian_to_int Utils.keccak256(get_sig(name, encode_types))
      end

      private

      def logger
        @logger ||= Logger.new 'eth.abi.contract_translator'
      end

      def get_sig(name, encode_types)
        "#{name}(#{encode_types.map {|x| canonical_type(x) }.join(',')})"
      end

      def canonical_type(x)
        case x
        when /\A(uint|int)(\[.*\])?\z/
          "#{$1}256#{$2}"
        when /\A(fixed|ufixed)(\[.*\])?\z/
          "#{$1}128x128#{$2}"
        else
          x
        end
      end

      def basename(n)
        i = n.index '('
        i ? n[0,i] : n
      end

    end
  end
end
