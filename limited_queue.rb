class LimitedQueue
  def initialize(max_size)
    @arr = []
    @max_size = max_size
  end

  def push(item)
    @arr << item
    if @arr.size > @max_size
      @arr.shift
    end
  end

  def end_with?(str)
    @arr.last(str.size).join == str
  end
end
