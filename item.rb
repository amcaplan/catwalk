class Item
  attr_reader :symbol, :start_time

  TEMPORARY_ITEMS = {
    👟: { name: :shoe,    duration: 10 },
    🦆: { name: :duck,    duration: 20, score_multiplier: 2 },
    🐦: { name: :bird,    duration: 15, score_multiplier: 3 },
    🌀: { name: :cyclone, duration: 2 }
  }
  MAX_DURATION = TEMPORARY_ITEMS.each_value.map { |item| item[:duration] }.max

  def initialize(symbol)
    @symbol = symbol
    @start_time = Time.now
  end

  def active?
    expiration > Time.now
  end

  def expiration
    start_time + TEMPORARY_ITEMS[symbol][:duration]
  end

  def score_multiplier
    TEMPORARY_ITEMS[symbol][:score_multiplier] || 1
  end

  TEMPORARY_ITEMS.each do |symbol, data|
    define_method("#{data[:name]}?") do
      data[:name] == TEMPORARY_ITEMS[self.symbol][:name]
    end
  end
end
