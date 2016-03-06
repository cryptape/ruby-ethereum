# -*- encoding : ascii-8bit -*-

require 'test_helper'

class CoreExtModuleTest < Minitest::Test

  class LruCacheTest
    attr :count

    def fire(a, b)
      @count ||= 0
      @count += 1
      a + b
    end

    def bomb(a, b)
      @count ||= 0
      @count += 1
      a + b
    end
    lru_cache :bomb, 100

    def shoot(a, b)
      @count ||= 0
      @count += 1
      a * b
    end
    lru_cache :shoot, 50
  end

  def test_lru_cache
    test1 = LruCacheTest.new
    100.times {|i| test1.fire(0, 0) }
    assert_equal 100, test1.count

    test2 = LruCacheTest.new
    100.times {|i| test2.bomb(0, 0) }
    assert_equal 1, test2.count

    100.times {|i| test2.bomb(i, i) }
    assert_equal 100, test2.count

    100.times {|i| test2.bomb(i, i) }
    assert_equal 100, test2.count

    50.times {|i| assert_equal test1.bomb(i, i), test2.bomb(i, i) }

    50.times {|i| test2.shoot(i, i) }
    50.times {|i| assert_equal test1.bomb(i, i), test2.bomb(i, i) }
    50.times {|i| assert_equal test1.shoot(i, i), test2.shoot(i, i) }

    assert_equal 2, LruCacheTest.instance_variable_get(:@_lru_caches).size
  end

end
