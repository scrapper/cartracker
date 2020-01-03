#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ReverseGeoCoder_spec.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'spec_helper'

require 'cartracker/ReverseGeoCoder'

describe CarTracker::ReverseGeoCoder do

  before(:all) do
    create_working_dirs
    create_store
  end

  after(:all) do
    cleanup
  end

  it 'should reverse lookup some coordinates in major cities' do
    coordinates = [
      [ 51.507402, -0.127663 ], # London
      [ 48.865751, 2.341184 ], # Paris
      [ 52.516280, 13.377638 ], # Berlin
      [ 41.902701, 12.496246 ] # Rome
    ]

    rgc = CarTracker::ReverseGeoCoder.new(@store)

    start_time = Time.now
    coordinates.each do |latitude, longitude|
      latitude = randomize(latitude)
      longitude = randomize(longitude)

      rgc.map_to_address(latitude, longitude)
    end
    expect(Time.now - start_time).to be >= 3
  end

  #it 'should lookup 50 random places in Munich' do
  #  latitude = 48.135094
  #  longitude = 11.576312

  #  rgc = CarTracker::ReverseGeoCoder.new(@store)

  #  0.upto(50) do
  #    lat = randomize(latitude)
  #    lon = randomize(longitude)

  #    puts "#{rgc.request_from_nominatim(lat, lon)},"
  #    sleep 1
  #  end
  #end

  def randomize(coord)
    coord + (rand(2000) - 1000) / 4800.0
  end

end

