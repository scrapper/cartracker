#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = GeoGridStore_spec.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'spec_helper'

require 'cartracker/GeoGridStore'

describe CarTracker::GeoGridStore do

  before(:all) do
    create_working_dirs
    create_store
    @store['ggs'] = @ggs = @store.new(CarTracker::GeoGridStore)
    locations_file = File.join(File.dirname(__FILE__), 'munich_locations.json')
    locations = JSON.parse(File.read(locations_file))

    @records = []
    locations.each do |loc|
      @records << @ggs.add(loc.to_json)
    end
  end

  after(:all) do
    cleanup
  end

  it 'should have stored the locations sorted by tiles' do
    lat_row_lengths = {
      479 => 4,
      480 => 5,
      481 => 5,
      482 => 3,
      483 => 4
    }
    expect(@ggs.by_latitude.length).to eql(5)
    @ggs.by_latitude.each do |idx, lon_row|
      expect(lon_row.length).to eql(lat_row_lengths[idx])
    end
  end

  it 'should find all records by their exact coordinates' do
    @records.each do |r|
      expect(@ggs.look_up(r.latitude, r.longitude)).to be(r)
    end
  end

  it 'should find a record with a close-by coordinate' do
    record = @ggs.look_up(48.1205901, 11.5138059)
    expect(record.street).to eql('Preßburger Straße')
  end

  it 'should not find a record for coordinates that are too far away' do
    expect(@ggs.look_up(48.1225901, 11.5138059)).to be_nil
  end

end

