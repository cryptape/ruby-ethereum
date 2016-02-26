# -*- encoding : ascii-8bit -*-

require 'lru_redux'

class Module

  def lru_cache(meth, n)
    @_lru_caches ||= {}
    @_lru_caches[meth] ||= LruRedux::Cache.new n
    cache = @_lru_caches[meth]

    origin_meth = "#{meth}_without_cache"
    self.send :alias_method, origin_meth, meth

    self.send(:define_method, meth) do |*args|
      cache[args] ||= send(origin_meth, *args)
    end
  end

end
