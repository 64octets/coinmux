class Coin2Coin::FreenetEvent
  attr_accessor :error, :data
  
  def initialize(params = {})
    params.each do |key, value|
      send("#{key}=", value)
    end
  end
end
