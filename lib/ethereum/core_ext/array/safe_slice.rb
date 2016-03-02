# -*- encoding : ascii-8bit -*-

class Array
  def safe_slice(*args)
    if args.size > 1 || args.first.instance_of?(Range)
      slice(*args) || []
    else
      slice(*args)
    end
  end
end
