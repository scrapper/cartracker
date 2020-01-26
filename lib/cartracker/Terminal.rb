#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Terminal.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'io/console'
require 'stringio'

module CarTracker

  class Terminal

    KEYSTROKES = {
      "\r" => 'Return',
      "\t" => 'Tab',
      "\e" => 'Escape',
      "\e[A" => 'ArrowUp',
      "\e[B" => 'ArrowDown',
      "\e[C" => 'ArrowRight',
      "\e[D" => 'ArrowLeft'
    }
    KEYCODES = KEYSTROKES.invert

    def initialize(out = STDOUT, inp = STDIN)
      @out = out
      @inp = inp
    end

    def reset
      send("\ec")
    end

    def clear
      send("\e[H\e[2J")
    end

    def size
      if @out.respond_to?('winsize')
        @out.winsize
      else
        IO.console.winsize
      end
    end

    def lines
      size[0]
    end

    def columns
      size[1]
    end

    def get_cusor_position
      send("\e[6n")
      answer = receive
      line, column = answer[2..-1].split(';')
      [ line.to_i, column.to_i ]
    end

    def set_cursor_position(line, column)
      if line <= 0 || line > lines
        raise RuntimeError, "Bad line for setting cursor position: #{line}"
      end
      if column <= 0 || column > columns
        raise RuntimeError, "Bad column for setting cursor position: " +
          "#{column}"
      end
      send("\e[#{line};#{column}H")
    end

    def hide_cursor
      send("\e[?25l")
    end

    def show_cursor
      send("\e[?25h")
    end

    def echo_on
      send("\e[12l")
    end

    def echo_off
      send("\e[12h")
    end

    def attributes_off
      send("\e[0m")
    end

    def bold_on
      send("\e[1m")
    end

    def low_intensity_on
      send("\e[2m")
    end

    def underline_on
      send("\e[4m")
    end

    def reverse_on
      send("\e[7m")
    end

    def getc
      str = @inp.getch

      if str == "\e"
        begin
          str << @inp.read_nonblock(3)
        rescue IO::EAGAINWaitReadable
        end
      end

      return KEYSTROKES[str] || str
    end

    def puts(str = '')
      @out.puts(str)
    end

    private

    def send(sequence)
      @out.print sequence
      @out.flush
    end

    def receive
      s = ''
      while (c = @inp.getc) != 'R'
        if c.nil?
          raise RuntimeError, "Could not receive cursor position " +
            "sequence: '#{s}'"
        end
        s += c if c
      end
      s
    end

  end

end

