# -*- encoding : ascii-8bit -*-

require 'json'

module Ethereum
  module ABI
    class ContractTranslator

      def initialize(full_signature)
        @v = {
          function_data: {},
          event_data: {}
        }

        if full_signature.instance_of?(String)
          full_signature = JSON.parse full_signature
        end

        full_signature.each do |sig_item|
          next if sig_item['type'] == 'constructor'

          encode_types = sig_item['inputs'].map {|f| f['type'] }
          signature = sig_item['inputs'].map {|f| [f['type'], f['name']] }
          name = sig_item['name']

          if name =~ /\(/
            name = name[0, name.index('(')]
          end

          # TODO: removable?
          #if @v.has_key?(name.to_sym)
          #  i = 2
          #  i += 1 while @v.has_key?(:"#{name}#{i}")
          #  name += i.to_s

          #  logger.warn "multiple methods with the same name. Use #{name} to call #{sig_item['name']} with types #{encode_types}"
          #end

          if sig_item['type'] == 'function'
            decode_types = sig_item['outputs'].map {|f| f['type'] }
            is_unknown_type = sig_item['outputs'].size.true? && sig_item['outputs'][0]['name'] == 'unknown_out'
            function_data[name.to_sym] = {
              prefix: method_id(name, encode_types),
              encode_types: encode_types,
              decode_types: decode_types,
              is_unknown_type: is_unknown_type,
              is_constant: sig_item.fetch('constant', false),
              signature: signature
            }
          elsif sig_item['type'] == 'event'
            indexed = sig_item['inputs'].map {|f| f['indexed'] }
            names = sig_item['inputs'].map {|f| f['name'] }

            event_data[event_id(name, encode_types)] = {
              types: encode_types,
              name: name,
              names: names,
              indexed: indexed,
              anonymous: sig_item.fetch('anonymous', false)
            }
          end
        end
      end

      def encode(name, args)
        fdata = function_data[name.to_sym]
        id = Utils.zpad(Utils.encode_int(fdata[:prefix]), 4)
        calldata = ABI.encode_abi fdata[:encode_types], args
        "#{id}#{calldata}"
      end

      def decode(name, data)
        fdata = function_data[name.to_sym]

        if fdata[:is_unknown_type]
          i = 0
          o = []

          while i < data.size
            o.push Utils.to_signed(Utils.big_endian_to_int(data[i,32]))
            i += 32
          end

          return 0 if o.empty?
          o.size == 1 ? o[0] : o
        else
          ABI.decode_abi fdata[:decode_types], data
        end
      end

      def function_data
        @v[:function_data]
      end

      def event_data
        @v[:event_data]
      end

      def function(name)
        function_data[name.to_sym]
      end

      def event(name, encode_types)
        event_data[event_id(name, encode_types)]
      end

      def is_unknown_type(name)
        function_data[name.to_sym][:is_unknown_type]
      end

      def listen(log, noprint=false)
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

    end
  end
end
