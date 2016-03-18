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

  SIXTEN_CODE = <<-EOF
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
    @s.block.set_code c, Serpent.compile_lll(SIXTEN_CODE)
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

    c
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

  HEDGE_CODE = <<-EOF
    extern datafeed: [get:[int256]:int256, set:[int256,int256]:int256]

    data partyone
    data partytwo
    data hedgeValue
    data datafeed
    data index
    data fiatValue
    data maturity

    def main(datafeed, index):
        if !self.partyone:
            self.partyone = msg.sender
            self.hedgeValue = msg.value
            self.datafeed = datafeed
            self.index = index
            return(1)
        elif !self.partytwo:
            ethvalue = self.hedgeValue
            if msg.value >= ethvalue:
                self.partytwo = msg.sender
            c = self.datafeed.get(self.index)
            othervalue = ethvalue * c
            self.fiatValue = othervalue
            self.maturity = block.timestamp + 500
            return(othervalue)
        else:
            othervalue = self.fiatValue
            ethvalue = othervalue / self.datafeed.get(self.index)
            if ethvalue >= self.balance:
                send(self.partyone, self.balance)
                return(3)
            elif block.timestamp > self.maturity:
                send(self.partytwo, self.balance - ethvalue)
                send(self.partyone, ethvalue)
                return(4)
            else:
                return(5)
  EOF
  def test_hegde_code
    c = test_data_feeds
    c2 = @s.abi_contract HEDGE_CODE, sender: Tester::Fixture.keys[0]

    # Have the first party register, sending 10**16 wei and asking for a hedge
    # using currency code 500.
    o1 = c2.main c.address, 500, value: 10**16
    assert_equal 1, o1

    # Have the second party register. It should receive the amount of units of
    # the second currency that it is entitled to. Note that from the previous
    # test this is set to 726.
    o2 = c2.main 0, 0, value: 10**16, sender: Tester::Fixture.keys[2]
    assert_equal 7260000000000000000, o2

    snapshot = @s.snapshot

    # Set the price of the asset down to 300 wei.
    o3 = c.set 500, 300
    assert_equal 1, o3

    # Finalize the contract. Expect code 3, meaning a margin call
    o4 = c2.main 0, 0
    assert_equal 3, o4

    @s.revert snapshot

    # Don't change the price. Finalize, and expect code 5, meaning the time has
    # not expired yet.
    o5 = c2.main 0, 0
    assert_equal 5, o5

    # Mine ten blocks, and try. Expect code 4, meaning a normal execution where
    # both get their share.
    @s.mine n: 100, coinbase: Tester::Fixture.accounts[3]
    o6 = c2.main 0, 0
    assert_equal 4, o6
  end

  LIFO_CODE = <<-EOF
    def init():
        self.storage[0] = 10

    def f1():
        self.storage[0] += 1

    def f2():
        self.storage[0] *= 10
        self.f1()
        self.storage[0] *= 10

    def f3():
        return(self.storage[0])
  EOF
  def test_lifo
    c = @s.abi_contract LIFO_CODE
    c.f2
    assert_equal 1010, c.f3
  end

  SUICIDER_CODE = <<-EOF
    def mainloop(rounds):
        self.storage[15] = 40
        self.suicide()
        i = 0
        while i < rounds:
            i += 1
            self.storage[i] = i

    def entry(rounds):
        self.storage[15] = 20
        self.mainloop(rounds, gas=msg.gas - 600)

    def ping_ten():
        return(10)

    def suicide():
        suicide(0)

    def ping_storage15():
        return(self.storage[15])
  EOF
  def test_suicider
    c = @s.abi_contract SUICIDER_CODE

    prev_gas_limit = Tester::Fixture.gas_limit
    Tester::Fixture.gas_limit = 200000

    # Run normally: suicide processes, so the attempt to ping the contract
    # fails.
    c.entry 5
    assert_equal nil, c.ping_ten

    c = @s.abi_contract SUICIDER_CODE

    # Run the suicider in such a way that it suicides in a sub-call, then runs
    # out of gas, leading to a revert of the suicide and storage mutation.
    c.entry 8000

    # Check that the suicide got reverted.
    assert_equal 10, c.ping_ten

    # Check that the storage op got reverted
    assert_equal 20, c.ping_storage15
  ensure
    Tester::Fixture.gas_limit = prev_gas_limit
  end

  REVERTER_CODE = <<-EOF
    def entry():
        self.non_recurse(gas=100000)
        self.recurse(gas=100000)

    def non_recurse():
        send(7, 9)
        self.storage[8080] = 4040
        self.storage[160160] = 2020

    def recurse():
        send(8, 9)
        self.storage[8081] = 4039
        self.storage[160161] = 2019
        self.recurse()
        while msg.gas > 0:
            self.storage["waste_some_gas"] = 0
  EOF
  def test_reverter
    c = @s.abi_contract REVERTER_CODE, endowment: 10**15
    c.entry

    assert_equal 4040, @s.block.get_storage_data(c.address, 8080)
    assert_equal 9, @s.block.get_balance(Utils.zpad_int(7, 20))
    assert_equal 0, @s.block.get_storage_data(c.address, 8081)
    assert_equal 0, @s.block.get_balance(Utils.zpad_int(8, 20))
  end

  ADD1_CODE = <<-EOF
    def main(x):
        self.storage[1] += x
  EOF
  CALLCODE_TEST_CODE = <<-EOF
    extern add1: [main:[int256]:int256]

    x = create("%s")
    x.main(6)
    x.main(4, call=code)
    x.main(60, call=code)
    x.main(40)
    return(self.storage[1])
  EOF
  def test_callcode
    with_file('callcode_add1', ADD1_CODE) do |filename|
      c = @s.contract(CALLCODE_TEST_CODE % filename)
      o = @s.send_tx Tester::Fixture.keys[0], c, 0
      assert_equal 64, Utils.big_endian_to_int(o)
    end
  end

  ARRAY_CODE = <<-EOF
    def main():
        a = array(1)
        a[0] = 1
        return(a, items=1)
  EOF
  def test_arrary
    c = @s.abi_contract ARRAY_CODE
    assert_equal [1], c.main
  end

  ARRAY_CODE2 = <<-EOF
    def main():
        a = array(1)
        something = 2
        a[0] = 1
        return(a, items=1)
  EOF
  def test_array2
    c = @s.abi_contract ARRAY_CODE2
    assert_equal [1], c.main
  end

  ARRAY_CODE3 = <<-EOF
    def main():
        a = array(3)
        return(a, items=3)
  EOF
  def test_array3
    c = @s.abi_contract ARRAY_CODE3
    assert_equal [0,0,0], c.main
  end

  CALLTEST_CODE = <<-EOF
    def main():
        self.first(1, 2, 3, 4, 5)
        self.second(2, 3, 4, 5, 6)
        self.third(3, 4, 5, 6, 7)

    def first(a, b, c, d, e):
        self.storage[1] = a * 10000 + b * 1000 + c * 100 + d * 10 + e

    def second(a, b, c, d, e):
        self.storage[2] = a * 10000 + b * 1000 + c * 100 + d * 10 + e

    def third(a, b, c, d, e):
        self.storage[3] = a * 10000 + b * 1000 + c * 100 + d * 10 + e

    def get(k):
        return(self.storage[k])
  EOF
  def test_calls
    c = @s.abi_contract CALLTEST_CODE
    c.main

    assert_equal 12345, c.get(1)
    assert_equal 23456, c.get(2)
    assert_equal 34567, c.get(3)

    c.first(4,5,6,7,8)
    assert_equal 45678, c.get(1)

    c.second(5,6,7,8,9)
    assert_equal 56789, c.get(2)
  end

  STORAGE_OBJECT_TEST_CODE = <<-EOF
    extern te.se: [ping:[]:_, query_chessboard:[int256,int256]:int256, query_items:[int256,int256]:int256, query_person:[]:int256[], query_stats:[int256]:int256[], testping:[int256,int256]:int256[], testping2:[int256]:int256]

    data chessboard[8][8]
    data users[100](health, x, y, items[5])
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    def ping():
        self.chessboard[0][0] = 1
        self.chessboard[0][1] = 2
        self.chessboard[3][0] = 3
        self.users[0].health = 100
        self.users[1].x = 15
        self.users[1].y = 12
        self.users[1].items[2] = 9
        self.users[80].health = self
        self.users[80].items[3] = self
        self.person.head = 555
        self.person.arms[0].elbow = 556
        self.person.arms[0].fingers[0] = 557
        self.person.arms[0].fingers[4] = 558
        self.person.legs[0] = 559
        self.person.arms[1].elbow = 656
        self.person.arms[1].fingers[0] = 657
        self.person.arms[1].fingers[4] = 658
        self.person.legs[1] = 659
        self.person.legs[1] += 1000

    def query_chessboard(x, y):
        return(self.chessboard[x][y])

    def query_stats(u):
        return([self.users[u].health, self.users[u].x, self.users[u].y]:arr)

    def query_items(u, i):
        return(self.users[u].items[i])

    def query_person():
        a = array(15)
        a[0] = self.person.head
        a[1] = self.person.arms[0].elbow
        a[2] = self.person.arms[1].elbow
        a[3] = self.person.legs[0]
        a[4] = self.person.legs[1]
        i = 0
        while i < 5:
            a[5 + i] = self.person.arms[0].fingers[i]
            a[10 + i] = self.person.arms[1].fingers[i]
            i += 1
        return(a:arr)

    def testping(x, y):
        return([self.users[80].health.testping2(x), self.users[80].items[3].testping2(y)]:arr)

    def testping2(x):
        return(x*x)
  EOF
  def test_storage_objects
    c = @s.abi_contract STORAGE_OBJECT_TEST_CODE
    c.ping

    assert_equal 1, c.query_chessboard(0, 0)
    assert_equal 2, c.query_chessboard(0, 1)
    assert_equal 3, c.query_chessboard(3, 0)

    assert_equal [100,0,0], c.query_stats(0)
    assert_equal [0,15,12], c.query_stats(1)

    assert_equal 0, c.query_items(1, 3)
    assert_equal 0, c.query_items(0, 2)
    assert_equal 9, c.query_items(1, 2)

    assert_equal [555, 556, 656, 559, 1659,
                  557,   0,   0,   0,  558,
                  657,   0,   0,   0,  658], c.query_person

    assert_equal [361, 441], c.testping(19, 21)
  end

  INFINITE_STORAGE_OBJECT_TEST_CODE = <<-EOF
    data chessboard[][8]
    data users[100](health, x, y, items[])
    data person(head, arms[](elbow, fingers[5]), legs[2])

    def ping():
        self.chessboard[0][0] = 1
        self.chessboard[0][1] = 2
        self.chessboard[3][0] = 3
        self.users[0].health = 100
        self.users[1].x = 15
        self.users[1].y = 12
        self.users[1].items[2] = 9
        self.person.head = 555
        self.person.arms[0].elbow = 556
        self.person.arms[0].fingers[0] = 557
        self.person.arms[0].fingers[4] = 558
        self.person.legs[0] = 559
        self.person.arms[1].elbow = 656
        self.person.arms[1].fingers[0] = 657
        self.person.arms[1].fingers[4] = 658
        self.person.legs[1] = 659
        self.person.legs[1] += 1000

    def query_chessboard(x, y):
        return(self.chessboard[x][y])

    def query_stats(u):
        return([self.users[u].health, self.users[u].x, self.users[u].y]:arr)

    def query_items(u, i):
        return(self.users[u].items[i])

    def query_person():
        a = array(15)
        a[0] = self.person.head
        a[1] = self.person.arms[0].elbow
        a[2] = self.person.arms[1].elbow
        a[3] = self.person.legs[0]
        a[4] = self.person.legs[1]
        i = 0
        while i < 5:
            a[5 + i] = self.person.arms[0].fingers[i]
            a[10 + i] = self.person.arms[1].fingers[i]
            i += 1
        return(a:arr)
  EOF
  def test_infinite_storage_objects
    c = @s.abi_contract INFINITE_STORAGE_OBJECT_TEST_CODE
    c.ping

    assert_equal 1, c.query_chessboard(0, 0)
    assert_equal 2, c.query_chessboard(0, 1)
    assert_equal 3, c.query_chessboard(3, 0)

    assert_equal [100,0,0], c.query_stats(0)
    assert_equal [0,15,12], c.query_stats(1)

    assert_equal 0, c.query_items(1, 3)
    assert_equal 0, c.query_items(0, 2)
    assert_equal 9, c.query_items(1, 2)

    assert_equal [555, 556, 656, 559, 1659,
                  557,   0,   0,   0,  558,
                  657,   0,   0,   0,  658], c.query_person
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
