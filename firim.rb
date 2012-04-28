require 'ncurses'
foobarrequire 'state_machine'
require 'logger'
require 'term/ansicolor'

Log = Logger.new('dev.log')


class RimWindow
  attr_accessor :mode, :screen, :form, :line, :commandStr, :lines, :column

  module Command
    def self.q win
      exit
    end

    def self.w win, name
      win.save(name)
    end
    
    def self.e win, name
      win.edit(name)
    end
  end

  include Term::ANSIColor

  state_machine :mode, :initial => :insert do
    event :normal do
      transition all => :normal
    end

    event :insert! do
      transition all => :insert
    end

    event :command do
      transition all => :command
    end

    state :command do
      def handle ch
        case ch
        when 127 # backspace
          screen.move(@line, @column)
        when 13 # return
          screen.addstr(ch.chr)
          args = commandStr.split
          Command.send(args.first, self, *args[1..-1])
          screen.move(@line, 4)
          normal!
        else                                                                   
          screen.addstr(ch.chr)
          commandStr << ch.chr
        end
      end
    end

    state :normal do
      def handle ch
        case ch
        when ?i
          insert!
          screen.move(@line, @column)
        when ?:
          command!
        end
      end
    end

    state :insert do
      def handle ch
        Log.info ch
        case ch
        when 127 # backspace
          @column -= 1
          @lines[@line] = @lines[@line][0..-2]
          screen.move(@line, @column)
        when 13 # return
          @line += 1
          @column = 4
          @lines << ""
          screen.addstr(ch.chr)
          update_lines
          screen.move(@line, 4)
        when 27 # Esc
          normal!
        else                                                                   
          screen.addstr(ch.chr)
          @lines[@line] << ch
          @column += 1
        end
      end
    end

    after_transition any => :insert do |window, transition|
      window.set_modeline("insert")
      window.screen.refresh
    end

    after_transition any => :command do |window, transition|
      window.set_modeline(":")
      window.commandStr = ""
      window.screen.refresh
    end

    after_transition any => :normal do |window, transition|
      window.set_modeline("normal")
      window.screen.refresh
    end
  end

  def clear_modeline
    Ncurses.mvprintw(34, 0, " "*120)
  end

  def save path
    File.open(path, 'w') do |f|
      f.write(@lines.join)
    end
    set_modeline("wrote #{path}")
  end

  def edit path
    normal!
    set_modeline("editing #{path}")
    @lines = File.readlines(path)
    draw_file
    @column = 4
    @line = 0
    screen.move(@line, @column)
  end

  def draw_file
    @lines[0..34].each_with_index do |line, i|
      Ncurses.mvprintw(i, 4, line)
    end
    update_lines
  end

  def update_lines
    @lines.each_with_index do |line, i|
      Ncurses.mvprintw(i, 0, sprintf("%3s ", i+1))
    end
  end

  def set_modeline(str)
    clear_modeline
    Ncurses.mvprintw(34, 0, str)
  end

  def initialize(screen)
    @commandStr = ""
    @line = 0
    @column = 4
    @lines = [""]
    @screen = screen
    super()
  end

  def mainloop
    screen.move(0, 0)
    update_lines
    screen.refresh()
    while(ch = screen.getch()) do
      handle(ch)
    end
  end

end


begin
  # initialize ncurses
  Ncurses.initscr
  Ncurses.cbreak           # provide unbuffered input
  Ncurses.noecho           # turn off input echoing
  Ncurses.nonl             # turn off newline translation
  Ncurses.stdscr.intrflush(false) # turn off flush-on-interrupt
  Ncurses.stdscr.keypad(true)     # turn on keypad mode

  RimWindow.new(Ncurses.stdscr).mainloop

ensure
  Ncurses.echo
  Ncurses.nocbreak
  Ncurses.nl
  Ncurses.endwin
end
