class Numeric

  BABBAGE  = 10**3
  LOVELACE = 10**6
  SHANNON  = 10**9
  SZABO    = 10**12
  FINNEY   = 10**15
  ETHER    = 10**18
  TURING   = 2**256

  def wei
    self
  end

  def babbage
    self * BABBAGE
  end

  def lovelace
    self * LOVELACE
  end

  def shannon
    self * SHANNON
  end

  def szabo
    self * SZABO
  end

  def finney
    self * FINNEY
  end

  def ether
    self * ETHER
  end

  def turing
    self * TURING
  end

end
