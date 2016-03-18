# -*- encoding : ascii-8bit -*-

require 'test_helper'
require 'serpent'

class ContractsTest < Minitest::Test
  include Ethereum

  def setup
    @s = Tester::State.new
  end

  TEST_EVM_CODE = <<-EOF
    def main(a,b):
      return (a ^ b)
  EOF
  def test_evm
    code = Tester::Language.format_spaces TEST_EVM_CODE
    evm_code = Serpent.compile code
    translator = ABI::ContractTranslator.new Serpent.mk_full_signature(code)

    data = translator.encode 'main', [2, 5]
    c = @s.evm evm_code
    o = translator.decode('main', @s.send_tx(Tester::Fixture.keys[0], c, 0, evmdata: data))
    assert_equal [32], o
  end

  TEST_SIXTEN_CODE = <<-EOF
    (with 'x 10
      (with 'y 20
        (with 'z 30
          (seq
            (set 'a (add (mul (get 'y) (get 'z)) (get 'x)))
            (return (ref 'a) 32)
          )
        )
      )
    )
  EOF
  def test_sixten
    c = Utils.decode_hex '1231231231231234564564564564561231231231'
    @s.block.set_code c, Serpent.compile_lll(TEST_SIXTEN_CODE)
    o = @s.send_tx(Tester::Fixture.keys[0], c, 0)
    assert_equal 610, Utils.big_endian_to_int(o)
  end

  TEST_WITH_CODE = <<-EOF
    def f1():
        o = array(4)
        with x = 5:
            o[0] = x
            with y = 7:
                o[1] = y
                with x = 8:
                    o[2] = x
            o[3] = x
        return(o:arr)


    def f2():
        with x = 5:
            with y = 7:
                x = 2
            return(x)

    def f3():
        with x = 5:
            with y = seq(x = 7, 2):
                return(x)

    def f4():
        o = array(4)
        with x = 5:
            o[0] = x
            with y = 7:
                o[1] = y
                with x = x:
                    o[2] = x
                    with y = x:
                        o[3] = y
        return(o:arr)
  EOF
  def test_with
    c = @s.abi_contract TEST_WITH_CODE
    assert_equal [5,7,8,5], c.f1
    assert_equal 2, c.f2
    assert_equal 7, c.f3
    assert_equal [5, 7, 5, 5], c.f4
  end

  MUL2_CODE = <<-EOF
    def double(v):
        log(v)
        return(v*2)
  EOF
  RETURNTEN_CODE = <<-EOF
    extern %s: [double:[int256]:int256]

    x = create("%s")
    log(x)
    return(x.double(5))
  EOF
  def test_returnten
    with_file('mul2', MUL2_CODE) do |filename|
      addr = @s.contract(RETURNTEN_CODE % [filename, filename])
      o = @s.send_tx Tester::Fixture.keys[0], addr, 0
      assert_equal 10, Utils.big_endian_to_int(o)
    end
  end

  INSET_INNER_CODE = <<-EOF
    def g(n):
        return(n + 10)

    def f(n):
        return n*2
  EOF
  INSET_OUTER_CODE = <<-EOF
    inset("%s")

    def foo():
        res = self.g(12)
        return res
  EOF
  def test_inset
    with_file('inset_inner', INSET_INNER_CODE) do |filename|
      c = @s.abi_contract(INSET_OUTER_CODE % filename)
      assert_equal 22, c.foo
      assert_equal 22, c.f(11)
    end
  end

  INSET_INNER_CODE2 = <<-EOF
    def g(n):
        return(n + 10)

    def f(n):
        return n*2
  EOF
  INSET_OUTER_CODE2 = <<-EOF
    def foo():
        res = self.g(12)
        return res

    inset("%s")
  EOF
  def test_inset2
    with_file('inset2_inner', INSET_INNER_CODE2) do |filename|
      c = @s.abi_contract(INSET_OUTER_CODE2 % filename)
      assert_equal 22, c.foo
      assert_equal 22, c.f(11)
    end
  end

  NAMECOIN_CODE = <<-EOF
    def main(k, v):
        if !self.storage[k]:
            self.storage[k] = v
            return(1)
        else:
            return(0)
  EOF
  def test_namecoin
    c = @s.abi_contract NAMECOIN_CODE

    assert_equal 1, c.main('george', 45)
    assert_equal 0, c.main('george', 20)
    assert_equal 1, c.main('harry', 60)
  end

  CURRENCY_CODE = <<-EOF
    data balances[2^160]

    def init():
        self.balances[msg.sender] = 1000

    def query(addr):
        return(self.balances[addr])

    def send(to, value):
        from = msg.sender
        fromvalue = self.balances[from]
        if fromvalue >= value:
            self.balances[from] = fromvalue - value
            self.balances[to] = self.balances[to] + value
            log(from, to, value)
            return(1)
        else:
            return(0)
  EOF
  def test_currency
    c = @s.abi_contract CURRENCY_CODE, sender: Tester::Fixture.keys[0]

    assert_equal 1, c.send(Tester::Fixture.accounts[2], 200)
    assert_equal 0, c.send(Tester::Fixture.accounts[2], 900)
    assert_equal 800, c.query(Tester::Fixture.accounts[0])
    assert_equal 200, c.query(Tester::Fixture.accounts[2])
  end

  DATA_FEED_CODE = <<-EOF
    data creator
    data values[]

    def init():
        self.creator = msg.sender

    def set(k, v):
        if msg.sender == self.creator:
            self.values[k] = v
            return(1)
        else:
            return(0)

    def get(k):
        return(self.values[k])
  EOF
  def test_data_feeds
    c = @s.abi_contract DATA_FEED_CODE, sender: Tester::Fixture.keys[0]

    assert_equal 0, c.get(500)
    assert_equal 1, c.set(500, 19)
    assert_equal 19, c.get(500)
    assert_equal 0, c.set(500, 726, sender: Tester::Fixture.keys[1])
    assert_equal 1, c.set(500, 726)
  end

  TOKEN_SOLIDITY_CODE = <<-EOF
    contract Token {
        address issuer;
        mapping (address => uint) balances;

        event Issue(address account, uint amount);
        event Transfer(address from, address to, uint amount);

        function Token() {
            issuer = msg.sender;
        }

        function issue(address account, uint amount) {
            if (msg.sender != issuer) throw;
            balances[account] += amount;
        }

        function transfer(address to, uint amount) {
            if (balances[msg.sender] < amount) throw;

            balances[msg.sender] -= amount;
            balances[to] += amount;

            Transfer(msg.sender, to, amount);
        }

        function getBalance(address account) constant returns (uint) {
            return balances[account];
        }
    }
  EOF
  def test_token_solidity
    c = @s.abi_contract TOKEN_SOLIDITY_CODE, language: :solidity

    assert_equal 0, c.getBalance(Tester::Fixture.accounts[2])
    c.issue Tester::Fixture.accounts[2], 100
    assert_equal 100, c.getBalance(Tester::Fixture.accounts[2])

    assert_raises(TransactionFailed) { c.issue Tester::Fixture.accounts[3], 100, sender: Tester::Fixture.keys[4] }
    assert_equal 0, c.getBalance(Tester::Fixture.accounts[3])

    c.transfer Tester::Fixture.accounts[3], 90, sender: Tester::Fixture.keys[2]
    assert_equal 90, c.getBalance(Tester::Fixture.accounts[3])

    assert_raises(TransactionFailed) { c.transfer Tester::Fixture.accounts[3], 90, sender: Tester::Fixture.keys[2] }
  end

  private

  def with_file(prefix, code)
    filename = "#{prefix}_#{Time.now.to_i}.se"
    f = File.open filename, 'w'
    f.write Tester::Language.format_spaces(code)
    f.close

    yield filename
  ensure
    FileUtils.rm filename
  end


end
