require 'singleton'

class Coin2Coin::Bitcoin
  include Singleton

  def current_block_height_and_nonce
    raise "TODO"
  end
end