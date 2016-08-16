# -*- encoding : ascii-8bit -*-

module Ethereum
  module Tester
    class ABIContract

      attr :address, :abi

      def initialize(test_state, abi_translator, address, listen: true, log_listener: nil, default_key: nil)
        @test_state = test_state
        @address = address
        @default_key = default_key || Fixture.keys.first
        @translator = abi_translator

        if listen
          listener = ->(log) {
            result = @translator.listen log, noprint: false
            log_listener(result) if result && log_listener
          }
          @test_state.block.log_listeners.push listener
        end

        @translator.function_data.each do |fn, _|
          generate_function fn
        end
      end

      def listen(x)
        @translator.listen x
      end

      private

      def generate_function(f)
        singleton_class.class_eval <<-EOF
        def #{f}(*args, **kwargs)
          sender = kwargs.delete(:sender) || @default_key
          to = @address
          value = kwargs.delete(:value) || 0
          evmdata = @translator.encode('#{f}', args)
          output = kwargs.delete(:output)

          o = @test_state._send_tx(sender, to, value, **kwargs.merge(evmdata: evmdata))

          if output == :raw
            outdata = o[:output]
          elsif o[:output].false?
            outdata = nil
          else
            outdata = @translator.decode '#{f}', o[:output]
            outdata = outdata.size == 1 ? outdata[0] : outdata
          end

          kwargs[:profiling].true? ? o.merge(output: outdata) : outdata
        end
        EOF
      end

    end
  end
end
