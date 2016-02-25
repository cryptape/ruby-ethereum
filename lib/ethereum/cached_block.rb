module Ethereum
  class CachedBlock < Block

    inherit_serializable_fields!

    def state_root=(*args)
      raise NotImplementedError
    end

    def revert(*args)
      raise NotImplementedError
    end

    def commit_state
      # do nothing
    end

    def hash
      Utils.big_endian_to_int full_hash
    end

    def full_hash
      @full_hash ||= super
    end

    private

    def set_account_item(*args)
      raise NotImplementedError
    end

  end
end
