# Must run first:
# # gem install timecop
require 'timecop'
require 'curses'

INSTRUCTIONS = <<~INSTRUCTIONS
  Press up and down to move the cat.
  Collect items to win points and
  change the game!

  🔄 Turn left
  💰 10 pts
  🐁 6 pts, creates skull
  💀 1 pt, clean mouse remains
  👟 Speed up
  🦆 Double scoring!
  🐦 Triple scoring!
  🌀 Cyclone mixes it up!

  'p' to pause/unpause
  'q' to quit
INSTRUCTIONS

TEMPORARY_ITEMS = {
  👟: 10,
  🦆: 20,
  🐦: 15,
  🌀: 2
}
map_items = [:🌱] * 200 + [:🔄] * 4 + [:💰] * 4 + [:🐁] * 2 + TEMPORARY_ITEMS.keys
SIDE_SIZE = 25
map = SIDE_SIZE.times.map { map_items.sample(SIDE_SIZE) }
EVENT_SYMBOLS = { :💰 => 10, :🐁 => 6, :🔄 => 2, :💀 => 1 }
WIDTH = map.first.size
HEIGHT = map.size
CAT_LOCATION = { y: HEIGHT / 2, x: WIDTH / 2 }
AVATAR = '🐈'
AVATARS = {
  'cat' => '🐈',
  'tiger' => '🐅',
  'camel' => '🐫',
  'horse' => '🐎',
  'whale' => '🐋',
  'frog' => '🐸'
}

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
main_window = Curses::Window.new(SIDE_SIZE + 3, 90, 0, 0)
main_width = WIDTH * 2 + 2
windows = {
  map: {
    last_updated: Time.now - 1,
    window: main_window.subwin(HEIGHT + 2, WIDTH * 2 + 2, 1, 0)
  }
}
side_panel = main_window.subwin(HEIGHT + 2, 90 - main_width, 1, main_width)
timer_window = main_window.subwin(1, 90, 0, 0)

def calculate_score(events)
  events.sum(&EVENT_SYMBOLS)
end

def score_for(event, active_items)
  EVENT_SYMBOLS[event] * score_multiplier(active_items)
end

def score_multiplier(active_items)
  multiplier = 1
  active_items.each do |entry|
    case entry[:item]
    when :🦆
      multiplier *= 2
    when :🐦
      multiplier *= 3
    end
  end
  multiplier
end

def render_instructions(side_panel)
  side_panel.clear
  INSTRUCTIONS.each_line.each_with_index do |line, index|
    side_panel.setpos(index + 1, 1)
    side_panel << "#{line}\n"
  end
  if $paused
    side_panel << "\n\n PAUSED"
  end
  side_panel.box('|', '-')
  side_panel.refresh
end

def render_frame(timer_window, side_panel, windows, state, init: nil)
  timer_window.clear
  timer_window.setpos(1, 1)
  timer_window << "#{'%.2f' % (init ? Time.now - init : 0).round(2)} seconds elapsed /"
  # mem = GetProcessMem.new
  # timer_window << " Memory used : #{mem.mb.round(0)} MB"
  # timer_window << " Min line size: #{state[:map].map(&:size).min}"
  timer_window << " Current multiplier: #{score_multiplier(active_items(**state))}x"
  timer_window << " Score: #{state[:score]}"
  timer_window << " Available Items: #{state[:map].map(&:join).join.gsub('🌱','').size}"
  timer_window.refresh
  render_instructions(side_panel)
  windows.each do |label, window_data|
    window = window_data[:window]
    if state[:last_updated] > window_data[:last_updated]
      window.clear
      window_data[:last_updated] = Time.now
      state[:map].each_with_index do |line, index|
        window.setpos(index + 1, 1)
        if index == CAT_LOCATION[:y]
          line = line.dup
          line[CAT_LOCATION[:x]] = AVATAR
        end
        window << line.join
      end
      window.box('|', '-')
      window.refresh
    end
  end
end

def active_items(temp_items:, **)
  cur_time = Time.now
  current_temp_item_index = temp_items.bsearch_index { |entry| entry[:time] - 20 > cur_time }
  temp_items[current_temp_item_index..-1].select { |entry| entry[:end_time] > cur_time }
end

def apply_tornado!(state)
  return if active_items(**state).none? { |entry| entry[:item] == :🌀 }
  state[:map] = state[:map].flatten.shuffle.each_slice(SIDE_SIZE).to_a
end

thread1 = Thread.new do
  sleep initial_sleep - 0.1
  loop do
    next if $paused
    state[:mutex].synchronize do
      cur_time = Time.now
      current_symbol = state[:map][CAT_LOCATION[:y]][CAT_LOCATION[:x]]
      if EVENT_SYMBOLS.key?(current_symbol)
        state[:events] << current_symbol
        state[:score] += score_for(current_symbol, active_items(**state))
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
      apply_tornado!(state)
      state[:last_updated] = Time.now
    end
    sleep(1.0/(5.0 * [(2 * active_items(**state).count { |entry| entry[:item] == :👟 }), 1].max))
  rescue => e
    File.write('./error.txt', e.full_message)
    exit
  end
end

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

thread2 = Thread.new do
  sleep initial_sleep - 0.1
  queue = LimitedQueue.new(10)
  loop do
    input = Curses.getch
    queue.push(input)
    AVATARS.each do |code, avatar|
      if queue.end_with?(code)
        AVATAR.replace(avatar)
      end
    end
    state[:mutex].synchronize do
      case input
      when 'A'
        state[:map] = state[:map].rotate(-1)
      when 'B'
        state[:map] = state[:map].rotate(1)
      when 'p'
        $paused = !$paused
        if $paused
          Timecop.freeze
        else
          Timecop.travel
        end
      when 'q'
        main_window.close
        Curses.close_screen
        puts "You collected:"
        state[:events].tally.each do |item, count|
          puts "#{item} #{count}"
        end
        puts "Your final score: #{state[:score]}"
        exit
      when 'D'
        main_window.close
        Curses.close_screen
        p state[:map]
        exit
      end
    end
  end
end

#sleep 0.01 until state.each_value.all? { |val| val[:string] }
render_frame(timer_window, side_panel, windows, state)
sleep initial_sleep

init = Time.now
loop do
  render_frame(timer_window, side_panel, windows, state, init: init)
  sleep 0.05
end

Curses.close_screen

