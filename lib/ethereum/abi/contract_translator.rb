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
          constructor_data: nil,
          function_data: {},
          event_data: {}
        }

        contract_interface.each do |desc|
          encode_types = desc['inputs'].map {|e| e['type'] }
          signature = desc['inputs'].map {|e| [e['type'], e['name']] }

          # type can be omitted, defaulting to function
          type = desc['type'] || 'function'
          case type
          when 'function'
            name = basename desc['name']
            decode_types = desc['outputs'].map {|e| e['type'] }
            @contract[:function_data][name] = {
              prefix: method_id(name, encode_types),
              encode_types: encode_types,
              decode_types: decode_types,
              is_constant: desc.fetch('constant', false),
              signature: signature
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

      def decode(name, data)
        desc = function_data[name]
        ABI.decode_abi desc[:decode_types], data
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

      def listen(log, noprint: false)
        return if log.topics.size == 0 || !event_data.has_key?(log.topics[0])

        data = event_data[log.topics[0]]
        types = data[:types]
        name = data[:name]
        names = data[:names]
        indexed = data[:indexed]
        indexed_types = types.zip(indexed).select {|(t, i)| i.true? }.map(&:first)
        unindexed_types = types.zip(indexed).select {|(t, i)| i.false? }.map(&:first)

        deserialized_args = ABI.decode_abi unindexed_types, log.data

        o = {}
        c1, c2 = 0, 0
        names.each_with_index do |n, i|
          if indexed[i].true?
            topic_bytes = Utils.zpad_int log.topics[c1+1]
            o[n] = ABI.decode_primitive_type ABI::Type.parse(indexed_types[c1]), topic_bytes
            c1 += 1
          else
            o[n] = deserialized_args[c2]
            c2 += 1
          end
        end

        o['_event_type'] = name
        p o unless noprint

        o
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
        "#{name}(#{encode_types.map {|x| canonical_name(x) }.join(',')})"
      end

      def canonical_name(x)
        case x
        when /\A(uint|int)(\[.*\])?\z/
          "#{$1}256#{$2}"
        when /\A(real|ureal|fixed|ufixed)(\[.*\])?\z/
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
