require 'test_helper'

class EphemDBTest < Minitest::Test

  def test_ephem_db
    db = Ethereum::DB::EphemDB.new

    content = [1,32,255].product([0,1,32,255])
      .map {|(lk,lv)| [Random.new.bytes(lk), Random.new.bytes(lv)] }
      .to_h
    alt_content = content.keys
      .map {|k| [k, Random.new.bytes(32)] }
      .to_h

    content.each do |k, v|
      assert_equal false, db.has_key?(k)
      assert_equal nil, db.get(k)
    end

    content.each do |k, v|
      db.put k, v
      assert_equal true, db.has_key?(k)
      assert_equal v, db.get(k)
    end

    content.each do |k, v|
      db.put k, alt_content[k]
      assert_equal true, db.has_key?(k)
      assert_equal alt_content[k], db.get(k)
    end

    content.each do |k, v|
      db.delete k
      assert_equal false, db.has_key?(k)
      assert_equal nil, db.get(k)
    end
  end

end
