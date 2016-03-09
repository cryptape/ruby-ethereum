# -*- encoding : ascii-8bit -*-

module Ethereum

  class ChecksumError < StandardError; end
  class FormatError < StandardError; end
  class ValidationError < StandardError; end
  class ValueError < StandardError; end
  class AssertError < StandardError; end

  class UnknownParentError < StandardError; end
  class InvalidBlock < ValidationError; end
  class InvalidUncles < ValidationError; end

  class InvalidTransaction < ValidationError; end
  class UnsignedTransactionError < InvalidTransaction; end
  class InvalidNonce < InvalidTransaction; end
  class InsufficientStartGas < InvalidTransaction; end
  class InsufficientBalance < InvalidTransaction; end
  class BlockGasLimitReached < InvalidTransaction; end

end
