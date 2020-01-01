#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Ride.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'perobs'

require 'cartracker/FlexiTable'

module CarTracker

  class Ride < PEROBS::Object

    attr_persist :vehicle, :start_timestamp, :start_soc,
      :start_latitude, :start_longitude, :start_odometer, :start_temperature,
      :end_timestamp, :end_soc, :end_latitude, :end_longitude,
      :end_odometer, :end_temperature, :energy

    def initialize(p)
      super
    end

    def Ride::table_header(t)
      t.row([ 'Date', 'Duration', 'Distance', 'Consumption' ])
      t.set_column_attributes(
        [
          { :halign => :left },
          { :halign => :right },
          { :halign => :right },
          { :halign => :right, :format => Proc.new { |v| '%.1f' % v }}
        ])
    end

    def restore
    end

    def table_row(t)
      t.new_row
      t.cell(@start_timestamp.strftime('%Y-%d-%m'))
      t.cell(secs2hms(@end_timestamp - @start_timestamp))
      distance = @end_odometer - @start_odometer
      t.cell(distance)
      energy = @vehicle.soc2energy(@start_soc - @end_soc)
      t.cell(energy / (distance / 100.0))
    end

    def to_ary
      [
        @start_timestamp, @start_soc, @start_latitude, @start_longitude,
        @start_odometer, @start_temperature,
        @end_timestamp, @end_soc, @end_latitude, @end_longitude,
        @end_odometer, @end_temperature, @energy
      ]
    end

    private

    def secs2hms(secs)
      secs = secs.to_i
      s = secs % 60
      mins = secs / 60
      m = mins % 60
      h = mins / 60
      "#{h}:#{'%02d' % m}:#{'%02d' % s}"
    end

  end

end


