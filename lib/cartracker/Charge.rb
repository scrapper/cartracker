#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Charge.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'perobs'

module CarTracker

  class Charge < PEROBS::Object

    attr_persist :start_timestamp, :start_soc,
      :end_timestamp, :odometer, :end_soc, :energy, :type,
      :latitude, :longitude, :location

    def initialize(p)
      super
    end

    def restore
      if @latitude && @longitude && @location.nil?
        rgc = ReverseGeoCoder.new(@store)
        map_location_to_address(rgc)
      end
    end

    def Charge::table_header(t)
      t.row([ 'Date', 'Location', 'Odometer', 'SoC', 'Energy AC',
              'Engergy DC' ])
      t.set_column_attributes(
        [
          { :halign => :left },
          { :halign => :left },
          { :halign => :right },
          { :halign => :left},
          { :halign => :right,
            :format => Proc.new { |v| '%.1f' % v },
            :label => :ac},
          { :halign => :right,
            :format => Proc.new { |v| '%.1f' % v },
            :label => :dc }
        ])
    end

    def table_row(t)
      t.new_row
      t.cell(@start_timestamp.strftime('%Y-%d-%m'))
      t.cell(location_to_s(@location))
      t.cell(@odometer)
      t.cell("#{@start_soc} -> #{@end_soc}")
      if @type == 'AC'
        t.cell(@energy)
        t.cell(0.0)
      else
        t.cell(0.0)
        t.cell(@energy)
      end
    end

    def Charge::table_footer(t)
      t.row( [
        '', '', '', '',
        Proc.new { t.sum(:ac, 0, :ac, -1) },
        Proc.new { t.sum(:dc, 0, :dc, -1) }
      ])
    end

    def to_ary
      [
        @start_timestamp, @start_soc, @end_timestamp, @end_soc,
        @energy, @type, @latitude, @longitude
      ]
    end

    def map_location_to_address(rgc)
      if @latitude && @longitude
        self.location = rgc.map_to_address(@latitude / 1000000.0,
                                           @longitude / 1000000.0)
      end
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

