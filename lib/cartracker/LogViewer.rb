#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = LogViewer.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'cartracker/Terminal'

module CarTracker

  class LogViewer

    def initialize(rgc, vehicle)
      @rgc = rgc
      @vehicle = vehicle
    end

    def run
      log_entry_count = @vehicle.telemetry.size
      index = log_entry_count - 1
      c = nil
      t = Terminal.new
      loop do
        t.clear
        puts progress_bar(log_entry_count, index)
        puts @vehicle.show_status(@rgc, index)
        case t.getc
        when 'q'
          return
        when 'n', 'ArrowRight'
          index += 1
          index = log_entry_count - 1 if index >= log_entry_count
        when 'p', 'ArrowLeft'
          index -= 1
          index = 0 if index < 0
        end
      end
    end

    private

    def progress_bar(total, current)
      length = 40
      bar = '|' + '=' * length + '|'

      if total > 1 && current >= 0 && current < total
        position_in_bar = (length * current.to_f / total.to_f).to_i
        bar[1 + position_in_bar] = '#'
      end

      bar
    end

  end

end

