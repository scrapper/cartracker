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
require 'cartracker/ReverseGeoCoder'
require 'cartracker/TimeUtils'

module CarTracker

  class Ride < PEROBS::Object

    attr_persist :vehicle, :start_timestamp, :start_soc,
      :start_latitude, :start_longitude, :start_location,
      :start_odometer, :start_temperature,
      :end_timestamp, :end_soc, :end_latitude, :end_longitude, :end_location,
      :end_odometer, :end_temperature, :energy

    def initialize(p)
      super
    end

    def restore
      if (@start_latitude && @start_longitude && @start_location.nil?) ||
          (@end_latitude && @end_longitude && @end_location.nil?)
        rgc = ReverseGeoCoder.new(@store)
        map_locations_to_addresses(rgc)
      end
    end

    def map_locations_to_addresses(reverse_geo_coder)
      if @start_latitude && @start_longitude
        self.start_location = reverse_geo_coder.map_to_address(
          @start_latitude / 1000000.0, @start_longitude / 1000000.0)
      end
      if @end_latitude && @end_longitude
        self.end_location = reverse_geo_coder.map_to_address(
          @end_latitude / 1000000.0, @end_longitude / 1000000.0)
      end
    end

    def Ride::table_header(t)
      t.row([ 'Date', 'From', 'To', 'Duration', 'Distance', 'SoC',
              'Energy', 'Energy/100km' ])
      t.set_column_attributes(
        [
          { :halign => :left },
          { :halign => :left },
          { :halign => :left },
          { :halign => :right,
            :format => Proc.new { |v| TimeUtils::secs2hms(v) },
            :label => :duration },
          { :halign => :right, :label => :distance },
          { :halign => :left },
          { :halign => :right,
            :format => Proc.new { |v| '%.1f' % v },
            :label => :energy },
          { :halign => :right,
            :format => Proc.new { |v| '%.1f' % v } }
        ])
    end

    def table_row(t)
      t.new_row
      t.cell(@start_timestamp.strftime('%Y-%d-%m'))
      t.cell(location_to_s(@start_location))
      t.cell(location_to_s(@end_location))
      t.cell(@end_timestamp - @start_timestamp)
      distance = @end_odometer - @start_odometer
      t.cell(distance)
      t.cell("#{@start_soc} -> #{@end_soc}")
      energy = @vehicle.soc2energy(@start_soc - @end_soc)
      t.cell(energy)
      t.cell(energy / (distance / 100.0))
    end

    def Ride::table_footer(t)
      t.row( [
        '', '', '',
        Proc.new { t.sum(:duration, 0, :duration, -1) },
        Proc.new { t.sum(:distance, 0, :distance, -1) },
        '',
        Proc.new { t.sum(:energy, 0, :energy, -1) },
        Proc.new { t.foot_value(:energy, 0) / t.foot_value(:distance, 0) * 100 }
      ])
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

    def location_to_s(location)
      return '' unless location

      if location.street && !location.street.empty?
        "#{location.street}, #{location.city}"
      else
        "#{location.city}"
      end
    end

  end

end


