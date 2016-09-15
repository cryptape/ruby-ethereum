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
    pragma solidity >=0.4.0;
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
    @s.mine 100, coinbase: Tester::Fixture.accounts[3]
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
    assert_equal 9, @s.block.get_balance(Utils.int_to_addr(7))
    assert_equal 0, @s.block.get_storage_data(c.address, 8081)
    assert_equal 0, @s.block.get_balance(Utils.int_to_addr(8))
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

  FAIL1 = <<-EOF
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    x = self.person.arms[0]
  EOF
  FAIL2 = <<-EOF
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    x = self.person.arms[0].fingers
  EOF
  FAIL3 = <<-EOF
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    x = self.person.arms[0].fingers[4][3]
  EOF
  FAIL4 = <<-EOF
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    x = self.person.arms.elbow[0].fingers[4]
  EOF
  FAIL5 = <<-EOF
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    x = self.person.arms[0].fingers[4].nail
  EOF
  FAIL6 = <<-EOF
    data person(head, arms[2](elbow, fingers[5]), legs[2])

    x = self.person.arms[0].elbow.skin
  EOF
  FAIL7 = <<-EOF
    def return_array():
        return([1,2,3], items=3)

    def main():
        return(self.return_array())
  EOF
  def test_storagevar_fails
    @s.contract(FAIL1) rescue assert_match /Storage variable access not deep enough/, $!.to_s
    @s.contract(FAIL2) rescue assert_match /Too few array index lookups/, $!.to_s
    @s.contract(FAIL3) rescue assert_match /Too many array index lookups/, $!.to_s
    @s.contract(FAIL4) rescue assert_match /Too few array index lookups/, $!.to_s
    @s.contract(FAIL5) rescue assert_match /Invalid object member/, $!.to_s
    @s.contract(FAIL6) rescue assert_match /Invalid object member/, $!.to_s
  end

  def test_type_system_fails
    @s.contract(FAIL7) rescue assert_match /Please specify maximum/, $!.to_s
  end

  WORKING_RETURNARRAY_CODE = <<-EOF
    def return_array():
        return([1,2,3], items=3)

    def less():
        return(self.return_array(outitems=2):arr)

    def more():
        return(self.return_array(outitems=4):arr)

    def main():
        return(self.return_array(outitems=3):arr)
  EOF
  def test_returnarray_code
    c = @s.abi_contract WORKING_RETURNARRAY_CODE
    assert_equal [1,2,3], c.main
    assert_equal [1,2,0], c.less
    assert_equal [1,2,3], c.more
  end

  CROWDFUND_CODE = <<-EOF
    data campaigns[2^80](recipient, goal, deadline, contrib_total, contrib_count, contribs[2^50](sender, value))

    def create_campaign(id, recipient, goal, timelimit):
        if self.campaigns[id].recipient:
            return(0)
        self.campaigns[id].recipient = recipient
        self.campaigns[id].goal = goal
        self.campaigns[id].deadline = block.timestamp + timelimit

    def contribute(id):
        # Update contribution total
        total_contributed = self.campaigns[id].contrib_total + msg.value
        self.campaigns[id].contrib_total = total_contributed

        # Record new contribution
        sub_index = self.campaigns[id].contrib_count
        self.campaigns[id].contribs[sub_index].sender = msg.sender
        self.campaigns[id].contribs[sub_index].value = msg.value
        self.campaigns[id].contrib_count = sub_index + 1

        # Enough funding?
        if total_contributed >= self.campaigns[id].goal:
            send(self.campaigns[id].recipient, total_contributed)
            self.clear(id)
            return(1)

        # Expired?
        if block.timestamp > self.campaigns[id].deadline:
            i = 0
            c = self.campaigns[id].contrib_count
            while i < c:
                send(self.campaigns[id].contribs[i].sender, self.campaigns[id].contribs[i].value)
                i += 1
            self.clear(id)
            return(2)

    # Progress report [2, id]
    def progress_report(id):
        return(self.campaigns[id].contrib_total)

    # Clearing function for internal use
    def clear(self, id):
        if self == msg.sender:
            self.campaigns[id].recipient = 0
            self.campaigns[id].goal = 0
            self.campaigns[id].deadline = 0
            c = self.campaigns[id].contrib_count
            self.campaigns[id].contrib_count = 0
            self.campaigns[id].contrib_total = 0
            i = 0
            while i < c:
                self.campaigns[id].contribs[i].sender = 0
                self.campaigns[id].contribs[i].value = 0
                i += 1
  EOF
  def test_crowdfund
    c = @s.abi_contract CROWDFUND_CODE

    # Create a campaign with id 100
    c.create_campaign 100, 45, 100000, 2

    # Create a campaign with id 200
    c.create_campaign 200, 48, 100000, 2

    # Make some contributions
    c.contribute 100, value: 1, sender: Tester::Fixture.keys[1]
    assert_equal 1, c.progress_report(100)

    c.contribute 200, value: 30000, sender: Tester::Fixture.keys[2]
    c.contribute 100, value: 59049, sender: Tester::Fixture.keys[3]
    assert_equal 59050, c.progress_report(100)

    # Expect the 100001 units to be delivered to the destination account for
    # campaign 2.
    c.contribute 200, value: 70001, sender: Tester::Fixture.keys[4]
    assert_equal 100001, @s.block.get_balance(Utils.int_to_addr(48))

    mida1 = @s.block.get_balance Tester::Fixture.accounts[1]
    mida3 = @s.block.get_balance Tester::Fixture.accounts[3]

    # Mine 5 blocks to expire the campaign
    @s.mine 5

    # Ping the campaign after expiry to trigger refunds
    c.contribute 100, value: 1
    assert_equal mida1+1, @s.block.get_balance(Tester::Fixture.accounts[1])
    assert_equal mida3+59049, @s.block.get_balance(Tester::Fixture.accounts[3])
  end

  SAVELOAD_CODE = <<-EOF
    data store[1000]

    def kall():
        a = text("sir bobalot to the rescue !!1!1!!1!1")
        save(self.store[0], a, chars=60)
        b = load(self.store[0], chars=60)
        c = load(self.store[0], chars=33)
        return([a[0], a[1], b[0], b[1], c[0], c[1]]:arr)
  EOF
  def test_safeload
    c = @s.abi_contract SAVELOAD_CODE
    o = c.kall

    str = "sir bobalot to the rescue !!1!1!!1!1"
    first_part_int = Utils.big_endian_to_int str[0,32]
    last_part_int = Utils.big_endian_to_int Utils.rpad(str[32..-1], Constant::BYTE_ZERO, 32)
    byte_33_int = Utils.big_endian_to_int(Utils.rpad(str[32,1], Constant::BYTE_ZERO, 32))

    assert_equal first_part_int, o[0]
    assert_equal last_part_int, o[1]
    assert_equal first_part_int, o[2]
    assert_equal last_part_int, o[3]
    assert_equal first_part_int, o[4]
    assert_equal byte_33_int, o[5]
  end

  SAVELOAD_CODE2 = <<-EOF
    data buf
    data buf2
    data buf3

    mystr = text("01ab")
    save(self.buf, mystr:str)
    save(self.buf2, mystr, chars=4)
  EOF
  def test_saveload2
    c = @s.contract SAVELOAD_CODE2
    @s.send_tx Tester::Fixture.keys[0], c, 0
    assert_equal "01ab"+"\x00"*28, Utils.encode_int(@s.block.get_storage_data(c, 0))
    assert_equal "01ab"+"\x00"*28, Utils.encode_int(@s.block.get_storage_data(c, 1))
  end

  SDIV_CODE = <<-EOF
    def kall():
        return([2^255 / 2^253, 2^255 % 3]:arr)
  EOF
  def test_sdiv
    c = @s.abi_contract SDIV_CODE
    assert_equal [-4, -2], c.kall
  end

  BASIC_ARGCALL_CODE = <<-EOF
    def argcall(args:arr):
        log(1)
        o = (args[0] + args[1] * 10 + args[2] * 100)
        log(4)
        return o

    def argkall(args:arr):
        log(2)
        o = self.argcall(args)
        log(3)
        return o
  EOF
  def test_basic_argcall
    c = @s.abi_contract BASIC_ARGCALL_CODE
    assert_equal 375, c.argcall([5, 7, 3])
    assert_equal 376, c.argkall([6, 7, 3])
  end

  COMPLEX_ARGCALL_CODE = <<-EOF
    def argcall(args:arr):
        args[0] *= 2
        args[1] *= 2
        return(args:arr)

    def argkall(args:arr):
        return(self.argcall(args, outsz=2):arr)
  EOF
  def test_complex_argcall
    c = @s.abi_contract COMPLEX_ARGCALL_CODE
    assert_equal [4, 8], c.argcall([2, 4])
    assert_equal [6, 10], c.argkall([3, 5])
  end

  SORT_CODE = <<-EOF
    def sort(args:arr):
        if len(args) < 2:
            return(args:arr)
        h = array(len(args))
        hpos = 0
        l = array(len(args))
        lpos = 0
        i = 1
        while i < len(args):
            if args[i] < args[0]:
                l[lpos] = args[i]
                lpos += 1
            else:
                h[hpos] = args[i]
                hpos += 1
            i += 1
        x = slice(h, items=0, items=hpos)
        h = self.sort(x, outsz=hpos)
        l = self.sort(slice(l, items=0, items=lpos), outsz=lpos)
        o = array(len(args))
        i = 0
        while i < lpos:
            o[i] = l[i]
            i += 1
        o[lpos] = args[0]
        i = 0
        while i < hpos:
            o[lpos + 1 + i] = h[i]
            i += 1
        return(o:arr)
      EOF
  def test_sort
    c = @s.abi_contract SORT_CODE
    assert_equal [9], c.sort([9])
    assert_equal [5,9], c.sort([9,5])
    assert_equal [3,5,9], c.sort([9,3,5])
    assert_equal [29,80,112,112,234], c.sort([80,234,112,112,29])
  end

  INDIRECT_SORT_CODE = <<-EOF
    extern sorter: [sort:[int256[]]:int256[]]
    data sorter

    def init():
        self.sorter = create("%s")

    def test(args:arr):
        return(self.sorter.sort(args, outsz=len(args)):arr)
  EOF
  def test_indirect_sort
    with_file("indirect_sort", SORT_CODE) do |filename|
      c = @s.abi_contract(INDIRECT_SORT_CODE % filename)
      assert_equal [29,80,112,112,234], c.test([80,234,112,112,29])
    end
  end

  MULTIARG_CODE = <<-EOF
    def kall(a:arr, b, c:arr, d:str, e):
        x = a[0] + 10 * b + 100 * c[0] + 1000 * a[1] + 10000 * c[1] + 100000 * e
        return([x, getch(d, 0) + getch(d, 1) + getch(d, 2), len(d)]:arr)
  EOF
  def test_multiarg_code
    c = @s.abi_contract MULTIARG_CODE
    o = c.kall [1,2,3], 4, [5,6,7], "doge", 8
    assert_equal [862541, 'd'.ord+'o'.ord+'g'.ord, 4], o
  end

  PEANO_CODE = <<-EOF
    macro padd($x, psuc($y)):
        psuc(padd($x, $y))

    macro padd($x, z()):
        $x

    macro dec(psuc($x)):
        dec($x) + 1

    macro dec(z()):
        0

    macro pmul($x, z()):
        z()

    macro pmul($x, psuc($y)):
        padd(pmul($x, $y), $x)

    macro pexp($x, z()):
        one()

    macro pexp($x, psuc($y)):
        pmul($x, pexp($x, $y))

    macro fac(z()):
        one()

    macro fac(psuc($x)):
        pmul(psuc($x), fac($x))

    macro one():
        psuc(z())

    macro two():
        psuc(psuc(z()))

    macro three():
        psuc(psuc(psuc(z())))

    macro five():
        padd(three(), two())

    def main():
        return([dec(pmul(three(), pmul(three(), three()))), dec(fac(five()))]:arr)
  EOF
  def test_peano_macro
    c = @s.abi_contract PEANO_CODE
    assert_equal [27,120], c.main
  end

  TYPE_CODE = <<-EOF
    type f: [a,b,c,d,e]

    macro f($a) + f($b):
        f(add($a, $b))

    macro f($a) - f($b):
        f(sub($a, $b))

    macro f($a) * f($b):
        f(mul($a, $b) / 10000)

    macro f($a) / f($b):
        f(sdiv($a * 10000, $b))

    macro f($a) % f($b):
        f(smod($a, $b))

    macro f($v) = f($w):
        $v = $w

    macro(10) f($a):
        $a / 10000

    macro fify($a):
        f($a * 10000)

    a = fify(5)
    b = fify(2)
    c = a / b
    e = c + (a / b)
    return(e)
  EOF
  def test_types
    c = @s.contract TYPE_CODE
    assert_equal 5, Utils.big_endian_to_int(@s.send_tx(Tester::Fixture.keys[0], c, 0))
  end

  ECRECOVER_CODE = <<-EOF
    def test_ecrecover(h:uint256, v:uint256, r:uint256, s:uint256):
        return(ecrecover(h, v, r, s))
  EOF
  def test_ecrecover
    c = @s.abi_contract ECRECOVER_CODE

    priv = Utils.keccak256('somg big long brainwallet password')
    pub = PrivateKey.new(priv).to_pubkey

    msghash = Utils.keccak256('the quick brown fox jumps over the lazy dog')
    v, r, s = Secp256k1.recoverable_sign msghash, priv
    assert_equal true, Secp256k1.signature_verify(msghash, [v,r,s], pub)

    addr = Utils.keccak256(PublicKey.new(pub).encode(:bin)[1..-1])[12..-1]
    assert_equal PrivateKey.new(priv).to_address, addr

    assert_equal Utils.big_endian_to_int(addr), c.test_ecrecover(Utils.big_endian_to_int(msghash), v, r, s)
  end

  SHA256_CODE = <<-EOF
    def main():
        return([sha256(0, chars=0), sha256(3), sha256(text("doge"), chars=3), sha256(text("dog"):str), sha256([0,0,0,0,0]:arr), sha256([0,0,0,0,0,0], items=5)]:arr)
  EOF
  def test_sha256
    c = @s.abi_contract SHA256_CODE
    assert_equal [
        0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 - 2**256,
        0xd9147961436944f43cd99d28b2bbddbf452ef872b30c8279e255e7daafc7f946 - 2**256,
        0xcd6357efdd966de8c0cb2f876cc89ec74ce35f0968e11743987084bd42fb8944 - 2**256,
        0xcd6357efdd966de8c0cb2f876cc89ec74ce35f0968e11743987084bd42fb8944 - 2**256,
        0xb393978842a0fa3d3e1470196f098f473f9678e72463cb65ec4ab5581856c2e4 - 2**256,
        0xb393978842a0fa3d3e1470196f098f473f9678e72463cb65ec4ab5581856c2e4 - 2**256
    ], c.main
  end

  SHA3_CODE = <<-EOF
    def main():
        return([sha3(0, chars=0), sha3(3), sha3(text("doge"), chars=3), sha3(text("dog"):str), sha3([0,0,0,0,0]:arr), sha3([0,0,0,0,0,0], items=5)]:arr)
  EOF
  def test_sha3
    c = @s.abi_contract SHA3_CODE
    assert_equal [
        0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 - 2**256,
        0xc2575a0e9e593c00f959f8c92f12db2869c3395a3b0502d05e2516446f71f85b - 2**256,
        0x41791102999c339c844880b23950704cc43aa840f3739e365323cda4dfa89e7a,
        0x41791102999c339c844880b23950704cc43aa840f3739e365323cda4dfa89e7a,
        0xdfded4ed5ac76ba7379cfe7b3b0f53e768dca8d45a34854e649cfc3c18cbd9cd - 2**256,
        0xdfded4ed5ac76ba7379cfe7b3b0f53e768dca8d45a34854e649cfc3c18cbd9cd - 2**256
    ], c.main
  end

  TYPES_IN_FUNCTIONS_CODE = <<-EOF
    type fixedp: [a, b]

    macro fixedp($x) * fixedp($y):
        fixedp($x * $y / 2^64)

    macro fixedp($x) / fixedp($y):
        fixedp($x * 2^64 / $y)

    macro raw_unfixedp(fixedp($x)):
        $x / 2^64

    macro set(fixedp($x), $y):
        $x = 2^64 * $y

    macro fixedp($x) = fixedp($y):
        $x = $y

    def sqrdiv(a, b):
        return(raw_unfixedp((a / b) * (a / b)))
  EOF
  def test_types_in_functions
    c = @s.abi_contract TYPES_IN_FUNCTIONS_CODE
    assert_equal 156, c.sqrdiv(25,2)
  end

  MORE_INFINITES_CODE = <<-EOF
    data a[](b, c)

    def testVerifyTx():

        self.a[0].b = 33

        self.a[0].c = 55

        return(self.a[0].b)
  EOF
  def test_more_infinites
    c = @s.abi_contract MORE_INFINITES_CODE
    assert_equal 33, c.testVerifyTx
  end

  PREVHASHES_CODE = <<-EOF
    def get_prevhashes(k):
        o = array(k)
        i = 0
        while i < k:
            o[i] = block.prevhash(i)
            i += 1
        return(o:arr)
  EOF
  def test_prevhashes
    c = @s.abi_contract PREVHASHES_CODE
    @s.mine 7

    # Hashes of last 14 blocks including existing one
    o1 = c.get_prevhashes(14).map {|x| x % 2**256 }

    # Hash of self = 0, hash of blocks back to genesis as is, hash of blocks
    # before genesis block = 0
    t1 = [0] + @s.blocks[0..-2].reverse.map {|b| Utils.big_endian_to_int(b.full_hash) } + [0]*6
    assert_equal t1, o1

    @s.mine 256

    # Test 256 limit: only 1 <= g <= 256 generation ancestors get hashes shown
    o2 = c.get_prevhashes(270).map {|x| x % 2**256 }
    t2 = [0] + @s.blocks[-257..-2].reverse.map {|b| Utils.big_endian_to_int(b.full_hash) } + [0] * 13
    assert_equal t2, o2
  end

  ABI_CONTRACT_CODE = <<-EOF
    def mul2(a):
        return(a * 2)

    def returnten():
        return(10)
  EOF
  def test_abi_contract
    c = @s.abi_contract ABI_CONTRACT_CODE
    assert_equal 6, c.mul2(3)
    assert_equal 10, c.returnten
  end

  MCOPY_CODE = <<-EOF
    def mcopy_test(foo:str, a, b, c):
        info = string(32*3 + len(foo))
        info[0] = a
        info[1] = b
        info[2] = c
        mcopy(info+(items=3), foo, len(foo))
        return(info:str)
  EOF
  def test_mcopy
    c = @s.abi_contract MCOPY_CODE
    assert_equal Utils.zpad_int(5)+Utils.zpad_int(6)+Utils.zpad_int(259)+'123', c.mcopy_test('123', 5, 6, 259)
  end

  MCOPY_CODE2 = <<-EOF
    def mcopy_test():
        myarr = array(3)
        myarr[0] = 99
        myarr[1] = 111
        myarr[2] = 119

        mystr = string(96)
        mcopy(mystr, myarr, items=3)
        return(mystr:str)
  EOF
  def test_mcopy2
    c = @s.abi_contract MCOPY_CODE2
    assert_equal Utils.zpad_int(99)+Utils.zpad_int(111)+Utils.zpad_int(119), c.mcopy_test
  end

  ARRAY_SAVELOAD_CODE = <<-EOF
    data a[5]

    def array_saveload():
        a = [1,2,3,4,5]
        save(self.a[0], a, items=5)
        a = load(self.a[0], items=4)
        log(len(a))
        return(load(self.a[0], items=4):arr)
  EOF
  def test_saveload3
    c = @s.abi_contract ARRAY_SAVELOAD_CODE
    assert_equal [1,2,3,4], c.array_saveload
  end

  STRING_MANIPULATION_CODE = <<-EOF
    def f1(istring:str):
        setch(istring, 0, "a")
        setch(istring, 1, "b")
        return(istring:str)

    def t1():
        istring = text("cd")
        res = self.f1(istring, outchars=2)
        return([getch(res,0), getch(res,1)]:arr)  # should return [97,98]
  EOF
  def test_string_manipulation
    c = @s.abi_contract STRING_MANIPULATION_CODE
    assert_equal [97, 98], c.t1
  end

  MORE_INFINITE_STORAGE_OBJECT_CODE = <<-EOF
    data block[2^256](_blockHeader(_prevBlock))

    data numAncestorDepths

    data logs[2]

    def initAncestorDepths():
        self.numAncestorDepths = 2

    def testStoreB(number, blockHash, hashPrevBlock, i):
        self.block[blockHash]._blockHeader._prevBlock = hashPrevBlock

        self.logs[i] = self.numAncestorDepths


    def test2():
        self.initAncestorDepths()
        self.testStoreB(45, 45, 44, 0)
        self.testStoreB(46, 46, 45, 1)
        return ([self.logs[0], self.logs[1]]:arr)
  EOF
  def test_more_infinite_storage
    c = @s.abi_contract MORE_INFINITE_STORAGE_OBJECT_CODE
    assert_equal [2,2], c.test2
  end

  DOUBLE_ARRAY_CODE = <<-EOF
    def foo(a:arr, b:arr):
        i = 0
        tot = 0
        while i < len(a):
            tot = tot * 10 + a[i]
            i += 1
        j = 0
        tot2 = 0
        while j < len(b):
            tot2 = tot2 * 10 + b[j]
            j += 1
        return ([tot, tot2]:arr)

    def bar(a:arr, m:str, b:arr):
        return(self.foo(a, b, outitems=2):arr)
  EOF
  def test_double_array
    c = @s.abi_contract DOUBLE_ARRAY_CODE
    assert_equal [123,4567], c.foo([1,2,3], [4,5,6,7])
    assert_equal [123,4567], c.bar([1,2,3], "moo", [4,5,6,7])
  end

  ABI_LOGGING_CODE = <<-EOF
    event rabbit(x)
    event frog(y:indexed)
    event moose(a, b:str, c:indexed, d:arr)
    event chicken(m:address:indexed)

    def test_rabbit(eks):
        log(type=rabbit, eks)

    def test_frog(why):
        log(type=frog, why)

    def test_moose(eh, bee:str, see, dee:arr):
        log(type=moose, eh, bee, see, dee)

    def test_chicken(em:address):
        log(type=chicken, em)
  EOF
  def test_abi_logging
    c = @s.abi_contract ABI_LOGGING_CODE
    o = []

    @s.block.add_listener(->(x) {
      result = c.listen(x, noprint: false)
      result.delete('_from')
      o.push(result)
    })

    c.test_rabbit(3)
    assert_equal [{"_event_type" => "rabbit", "x" => 3}], o

    o.pop
    c.test_frog(5)
    assert_equal [{"_event_type" => "frog", "y" => 5}], o

    o.pop
    c.test_moose(7, "nine", 11, [13, 15, 17])
    assert_equal [{"_event_type" => "moose", "a" => 7, "b" => "nine", "c" => 11, "d" => [13, 15, 17]}], o

    o.pop
    c.test_chicken(Tester::Fixture.accounts[0])
    assert_equal [{"_event_type" => "chicken", "m" => Utils.encode_hex(Tester::Fixture.accounts[0])}], o
  end

  NEW_FORMAT_INNER_CODE = <<-EOF
    def foo(a, b:arr, c:str):
        return a * 10 + b[1]
  EOF
  NEW_FORMAT_OUTER_CODE = <<-EOF
    extern blah: [foo:[int256,int256[],bytes]:int256]

    def bar():
        x = create("%s")
        return x.foo(17, [3, 5, 7], text("dog"))
  EOF
  def test_new_format
    with_file("new_format", NEW_FORMAT_INNER_CODE) do |filename|
      c = @s.abi_contract(NEW_FORMAT_OUTER_CODE % filename)
      assert_equal 175, c.bar
    end
  end

  ABI_ADDRESS_OUTPUT_CODE = <<-EOF
    data addrs[]

    def get_address(key):
        return(self.addrs[key]:address)

    def register(key, addr:address):
        if not self.addrs[key]:
            self.addrs[key] = addr
  EOF
  def test_abi_address_output
    c = @s.abi_contract ABI_ADDRESS_OUTPUT_CODE
    c.register(123, '1212121212121212121212121212121212121212')
    c.register(123, '3434343434343434343434343434343434343434')
    c.register(125, '5656565656565656565656565656565656565656')
    assert '1212121212121212121212121212121212121212', c.get_address(123)
    assert '5656565656565656565656565656565656565656', c.get_address(125)
  end

  ABI_ADDRESS_CALLER_CODE = <<-EOF
    extern foo: [get_address:[int256]:address, register:[int256,address]:_]
    data sub

    def init():
        self.sub = create("%s")

    def get_address(key):
        return(self.sub.get_address(key):address)

    def register(key, addr:address):
        self.sub.register(key, addr)
  EOF
  def test_inner_abi_address_output
    with_file('inner_abi_address', ABI_ADDRESS_OUTPUT_CODE) do |filename|
      c = @s.abi_contract(ABI_ADDRESS_CALLER_CODE % filename)
      c.register(123, '1212121212121212121212121212121212121212')
      c.register(123, '3434343434343434343434343434343434343434')
      c.register(125, '5656565656565656565656565656565656565656')
      assert '1212121212121212121212121212121212121212', c.get_address(123)
      assert '5656565656565656565656565656565656565656', c.get_address(125)
    end
  end

  STRING_LOGGING_CODE = <<-EOF
    event foo(x:string:indexed, y:bytes:indexed, z:str:indexed)

    def moo():
        log(type=foo, text("bob"), text("cow"), text("dog"))
  EOF
  def test_string_logging
    c = @s.abi_contract STRING_LOGGING_CODE
    o = []

    @s.block.add_listener(->(x) {
      result = c.listen(x, noprint: false)
      result.delete('_from')
      o.push(result)
    })

    c.moo

    expect = [
      {"_event_type" => "foo",
       "x" => "bob", "__hash_x" => Utils.keccak256("bob"),
       "y" => "cow", "__hash_y" => Utils.keccak256("cow"),
       "z" => "dog", "__hash_z" => Utils.keccak256("dog")}
    ]
    assert_equal expect, o
  end

  PARAMS_CODE = <<-EOF
    data blah

    def init():
        self.blah = $FOO

    def garble():
        return(self.blah)

    def marble():
        return(text($BAR):str)
  EOF
  def test_params_contract
    c = @s.abi_contract PARAMS_CODE, FOO: 4, BAR: 'horse'
    assert_equal 4, c.garble
    assert_equal 'horse', c.marble
  end

  PREFIX_TYPES_IN_FUNCTIONS_CODE = <<-EOF
    type fixedp: fp_

    macro fixedp($x) * fixedp($y):
        fixedp($x * $y / 2^64)

    macro fixedp($x) / fixedp($y):
        fixedp($x * 2^64 / $y)

    macro raw_unfixedp(fixedp($x)):
        $x / 2^64

    macro set(fixedp($x), $y):
        $x = 2^64 * $y

    macro fixedp($x) = fixedp($y):
        $x = $y

    def sqrdiv(fp_a, fp_b):
        return(raw_unfixedp((fp_a / fp_b) * (fp_a / fp_b)))
  EOF
  def test_prefix_types_in_functions
    c = @s.abi_contract PREFIX_TYPES_IN_FUNCTIONS_CODE
    assert_equal 156, c.sqrdiv(25,2)
  end

  RIPEMD160_CODE = <<-EOF
  def main():
      return([ripemd160(0, chars=0), ripemd160(3), ripemd160(text("doge"), chars=3), ripemd160(text("dog"):str), ripemd160([0,0,0,0,0]:arr), ripemd160([0,0,0,0,0,0], items=5)]:arr)
  EOF

  def test_ripemd160
    c = @s.abi_contract RIPEMD160_CODE
    assert_equal [
      0x9c1185a5c5e9fc54612808977ee8f548b2258d31,
      0x44d90e2d3714c8663b632fcf0f9d5f22192cc4c8,
      0x2a5756a3da3bc6e4c66a65028f43d31a1290bb75,
      0x2a5756a3da3bc6e4c66a65028f43d31a1290bb75,
      0x9164cab7f680fd7a790080f2e76e049811074349,
      0x9164cab7f680fd7a790080f2e76e049811074349
    ], c.main
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
