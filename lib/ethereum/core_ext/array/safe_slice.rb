# -*- encoding : ascii-8bit -*-

class Array
  def safe_slice(*args)
    if args.size == 2
      return [] if args[1] == 0
      slice(args[0], args[1]) || []
    elsif args.size == 1
      if args[0].instance_of?(Range)
        slice(args[0]) || []
      else
        slice(args[0])
      end
    else
      slice(*args)
    end
  end
end
