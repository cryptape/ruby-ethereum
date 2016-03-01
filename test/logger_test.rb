# -*- encoding : ascii-8bit -*-

require 'test_helper'

class LoggerTest < Minitest::Test
  include Ethereum

  def test_logger_trace
    l = Minitest::Mock.new
    l.expect :info, nil, ["TRACE TEST a=1 b=2"]

    logger = Logger.new 'eth.test', l
    logger.trace('TEST', a: 1, b: 2)

    assert_raises(MockExpectationError) { l.verify }

    Logger.set_trace 'eth.test', true
    logger.trace('TEST', a: 1, b: 2)
    l.verify
  end

end
