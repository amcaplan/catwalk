# Must run first:
# # gem install timecop
require 'timecop'
require 'curses'
require __dir__ + '/limited_queue'
require __dir__ + '/item'

INSTRUCTIONS = <<~INSTRUCTIONS
  Press up and down to move the cat.
  Collect items to win points and
  change the game!

  🔄 Turn left
  💰 10 pts
  🐁 6 pts, creates skull
  💀 1 pt, clean mouse remains
  👟 Turbo boost
  🦆 Double scoring!
  🐦 Triple scoring!!
  🌀 Cyclone mixes it up!

  'p' to pause/unpause
  'q' to quit
INSTRUCTIONS

map_items = [:🌱] * 200 + [:🔄] * 4 + [:💰] * 4 + [:🐁] * 2 + Item::TEMPORARY_ITEMS.keys
special_items = map_items - [:🌱]
SIDE_SIZE = 25
map = SIDE_SIZE.times.map { map_items.sample(SIDE_SIZE) }
SCORES = { :💰 => 10, :🐁 => 6, :🔄 => 2, :💀 => 1 }
WIDTH = map.first.size
HEIGHT = map.size
CAT_LOCATION = { y: HEIGHT / 2, x: WIDTH / 2 }
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
  avatar: '🐈',
  events: [],
  temp_items: [],
  score: 0,
  last_updated: Time.now,
  frame_count: {
    second: Time.now.round,
    count: 0,
    last_frame_count: 0
  },
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

def score_for(event, active_items)
  SCORES[event] * score_multiplier(active_items)
end

def score_multiplier(active_items)
  active_items.inject(1) { |accum, item| accum * item.score_multiplier }
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
  # Track FPS
  cur_second = Time.now.round
  if state[:frame_count][:second] == cur_second
    state[:frame_count][:count] += 1
  else
    state[:frame_count][:second] = cur_second
    state[:frame_count][:last_frame_count] = state[:frame_count][:count]
    state[:frame_count][:count] = 1
  end

  timer_window.clear
  timer_window.setpos(1, 1)
  timer_window << "Time: #{'%.2f' % (init ? Time.now - init : 0).round(2)} / #{state[:frame_count][:last_frame_count]} FPS /"
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
          line[CAT_LOCATION[:x]] = state[:avatar]
        end
        window << line.join
      end
      window.box('|', '-')
      window.refresh
    end
  end
end

def active_items(temp_items:, **)
  earliest_active_start_time = Time.now - Item::MAX_DURATION
  current_temp_item_index =
    temp_items.bsearch_index { |i| i.start_time > earliest_active_start_time } || 0
  temp_items[current_temp_item_index..-1].select(&:active?).tap { |retval|
    File.write('active_items', retval.inspect)
  }
end

def apply_cyclone!(state)
  return if active_items(**state).none?(&:cyclone?)
  File.write('cyclone_items', active_items(**state))
  state[:map] = state[:map].flatten.shuffle.each_slice(SIDE_SIZE).to_a
end

thread1 = Thread.new do
  sleep initial_sleep - 0.1
  loop do
    next if $paused
    state[:mutex].synchronize do
      cur_time = Time.now
      current_symbol = state[:map][CAT_LOCATION[:y]][CAT_LOCATION[:x]]
      if SCORES.key?(current_symbol)
        state[:events] << current_symbol
        state[:score] += score_for(current_symbol, active_items(**state))
      elsif Item::TEMPORARY_ITEMS.key?(current_symbol)
        state[:events] << current_symbol
        state[:temp_items] << Item.new(current_symbol)
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
        state[:map].map! { |line| line.rotate(-1) }
      end
      # randomly add new item, approx. once every 3 cycles
      if rand(SIDE_SIZE * 3) == 1
        affected_line = state[:map].select { |line| line[0] == :🌱 }.sample
        affected_line[0] = special_items.sample if affected_line
      end
      apply_cyclone!(state)
      state[:last_updated] = Time.now
    end
    sleep(1.0/(5.0 * [(2 * active_items(**state).count(&:shoe?)), 1].max))
  rescue => e
    File.write('./error.txt', e.full_message)
    exit
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
        state[:avatar].replace(avatar)
      end
    end
    state[:mutex].synchronize do
      case input
      when 'A'
        state[:map].rotate!(-1)
      when 'B'
        state[:map].rotate!(1)
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
      when 's'
        state[:temp_items] << Item.new(:👟)
      when 'D'
        main_window.close
        Curses.close_screen
        p state
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

