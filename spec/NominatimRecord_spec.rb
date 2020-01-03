#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = NominatimRecord_spec.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'spec_helper'

require 'cartracker/NominatimRecord'

describe CarTracker::NominatimRecord do

  before(:all) do
    create_working_dirs
    create_store
  end

  after(:all) do
    cleanup
  end

  it 'should extract data from a Nominatim response' do
    record = @store.new(CarTracker::NominatimRecord)
    response = <<-EOT
{"place_id": 268333899,
 "licence":
  "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
 "osm_type": "node",
 "osm_id": 6600036324,
 "lat": "51.4510296",
 "lon": "11.3051494",
 "display_name":
  "Ionity Sangerhausen, A 38, Oberröblingen, Sangerhausen, Mansfeld-Südharz, Sachsen-Anhalt, 06526, Deutschland",
 "address":
  {"address29": "Ionity Sangerhausen",
   "road": "A 38",
   "suburb": "Oberröblingen",
   "town": "Sangerhausen",
   "county": "Mansfeld-Südharz",
   "state": "Sachsen-Anhalt",
   "postcode": "06526",
   "country": "Deutschland",
   "country_code": "de"},
 "boundingbox": ["51.4509296", "51.4511296", "11.3050494", "11.3052494"]}
 EOT
   record.nominatim_response = response
   record.extract_data_from_response

   expect(record.latitude).to be_within(0.001).of(51.4510296)
   expect(record.longitude).to be_within(0.001).of(11.3051494)
   expect(record.country).to eql('Deutschland')
   expect(record.zip_code).to eql('06526')
   expect(record.city).to eql('Sangerhausen')
   expect(record.street).to eql('A 38')
   expect(record.number).to eql('')
  end

end
