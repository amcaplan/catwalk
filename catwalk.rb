# require 'get_process_mem'
require 'curses'

TEMPORARY_ITEMS = {
  👟: 10,
  🦆: 20,
  🐦: 15
}
map_items = [:🌱] * 200 + [:🔄] * 4 + [:💰] * 4 + [:🐁] * 2 + TEMPORARY_ITEMS.keys
SIDE_SIZE = 25
map = SIDE_SIZE.times.map { map_items.sample(SIDE_SIZE) }
EVENT_SYMBOLS = { :💰 => 100, :🐁 => 60, :🔄 => 20, :💀 => 5 }
WIDTH = map.first.size
HEIGHT = map.size
CAT_LOCATION = { y: HEIGHT / 2, x: WIDTH / 2 }

initial_sleep = 2

state = {
  map: map,
  events: [],
  temp_items: [],
  score: 0,
  last_updated: Time.now,
  mutex: Mutex.new
}

Curses.init_screen
Curses.cbreak
Curses.noecho
main_window = Curses::Window.new(SIDE_SIZE + 3, 80, 0, 0)
windows = {
  map: {
    last_updated: Time.now - 1,
    window: main_window.subwin(HEIGHT + 2, WIDTH * 2 + 2, 1, 0)
  }
}
timer_window = main_window.subwin(1, 80, 0, 0)

def calculate_score(events)
  events.sum(&EVENT_SYMBOLS)
end

def score_for(event, active_items)
  score = EVENT_SYMBOLS[event]
  active_items.each do |item|
    case item
    when :🪀
      score *= 2
    when :🐦
      score *= 3
    end
  end
  score
end

def render_frame(timer_window, windows, state, init: nil)
  timer_window.clear
  timer_window.setpos(1, 1)
  timer_window << "#{'%.2f' % (Time.now - init).round(2)} seconds elapsed /" if init
  # mem = GetProcessMem.new
  # timer_window << " Memory used : #{mem.mb.round(0)} MB"
  timer_window << " Min line size: #{state[:map].map(&:size).min}"
  timer_window << " Score: #{state[:score]}"
  timer_window << " Available Items: #{state[:map].map(&:join).join.gsub('🌱','').size}"
  timer_window.refresh
  windows.each do |label, window_data|
    window = window_data[:window]
    if state[:last_updated] > window_data[:last_updated]
      window.clear
      window_data[:last_updated] = Time.now
      state[:map].each_with_index do |line, index|
        window.setpos(index + 1, 1)
        if index == CAT_LOCATION[:y]
          line = line.dup
          line[CAT_LOCATION[:x]] = :🐈
        end
        window << line.join
      end
      window.box('|', '-')
      window.refresh
    end
  end
end

thread1 = Thread.new do
  sleep initial_sleep - 0.1
  active_items = []
  loop do
    next if $paused
    state[:mutex].synchronize do
      cur_time = Time.now
      begin
        current_temp_item_index = state[:temp_items].bsearch_index { |entry| entry[:time] - 20 > cur_time }
      rescue => e
        File.write('./errors.txt', state[:temp_items].inspect)
      end
      active_items = state[:temp_items][current_temp_item_index..-1].select { |entry| entry[:end_time] > cur_time }
      current_symbol = state[:map][CAT_LOCATION[:y]][CAT_LOCATION[:x]]
      if EVENT_SYMBOLS.key?(current_symbol)
        state[:events] << current_symbol
        state[:score] += score_for(current_symbol, active_items)
      elsif TEMPORARY_ITEMS.key?(current_symbol)
        state[:events] << current_symbol
        state[:temp_items] << { time: cur_time, item: current_symbol, end_time: Time.now + TEMPORARY_ITEMS[current_symbol] }
      end
      # overwrite symbol
      state[:map][CAT_LOCATION[:y]][CAT_LOCATION[:x]] =
        case current_symbol
        when :🐁
          :💀
        else
          :🌱
        end
      # move
      case current_symbol
      when :🔄
        state[:map] = state[:map].transpose.map(&:reverse)
      else
        state[:map] = state[:map].map { |line| line.rotate(-1) }
      end
      # randomly add new item
      affected_line = state[:map].select { |line| line[0] == :🌱 }.sample
      affected_line[0] = map_items.sample if affected_line
      state[:last_updated] = Time.now
    end
    sleep(1.0/(7.0 * [(2 * active_items.count { |entry| entry[:item] == :👟 }), 1].max))
  rescue => e
    File.write('./error.txt', e.full_message)
    exit
  end
end

thread2 = Thread.new do
  sleep initial_sleep - 0.1
  loop do
    input = Curses.getch
    state[:mutex].synchronize do
      case input
      when 'A'
        state[:map] = state[:map].rotate(-1)
      when 'B'
        state[:map] = state[:map].rotate(1)
      when 'p'
        $paused = !$paused
      when 'q'
        main_window.close
        Curses.close_screen
        puts "You collected:"
        state[:events].tally.each do |item, count|
          puts "#{item} #{count}"
        end
        puts "Your final score: #{state[:score]}"
        exit
      when 'd'
        main_window.close
        Curses.close_screen
        p state[:map]
        exit
      end
    end
  end
end

#sleep 0.01 until state.each_value.all? { |val| val[:string] }
render_frame(timer_window, windows, state)
sleep initial_sleep

init = Time.now
loop do
  render_frame(timer_window, windows, state, init: init)
  sleep 0.05
end

Curses.close_screen

