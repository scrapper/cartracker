#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = NominatimRecord.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'perobs'

module CarTracker

  class NominatimError < RuntimeError
  end

  class NominatimRecord < PEROBS::Object

    attr_persist :latitude, :longitude, :country, :city, :zip_code, :street,
      :number, :description, :nominatim_response

    def initialize(p)
      super
    end

    def extract_data_from_response
      # Responses from Nominatim are in JSON format and look like this:
      #
      # {"place_id"=>268333899,
      #  "licence"=>
      #   "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
      #  "osm_type"=>"node",
      #  "osm_id"=>6600036324,
      #  "lat"=>"51.4510296",
      #  "lon"=>"11.3051494",
      #  "display_name"=>
      #   "Ionity Sangerhausen, A 38, Oberröblingen, Sangerhausen, Mansfeld-Südharz, Sachsen-Anhalt, 06526, Deutschland",
      #  "address"=>
      #   {"address29"=>"Ionity Sangerhausen",
      #    "road"=>"A 38",
      #    "suburb"=>"Oberröblingen",
      #    "town"=>"Sangerhausen",
      #    "county"=>"Mansfeld-Südharz",
      #    "state"=>"Sachsen-Anhalt",
      #    "postcode"=>"06526",
      #    "country"=>"Deutschland",
      #    "country_code"=>"de"},
      #  "boundingbox"=>["51.4509296", "51.4511296", "11.3050494", "11.3052494"]}
      begin
        response = JSON.parse(@nominatim_response)
      rescue JSON::ParserError => e
        raise NomatimError, "Cannot parse Nominatim response: #{e.message}"
      end

      unless response.include?('lat')
        raise NomatimError, "Nominatim record does not contain a latitude: " +
          "#{@nominatim_response}"
      end
      self.latitude = response['lat'].to_f
      if @latitude < -90.0 || @latitude > 90.0
        raise NomatimError, "Nominatim record latitude is out of range: " +
          "#{@nominatim_response}"
      end

      unless response.include?('lon')
        raise NomatimError, "Nominatim record does not contain a longitude: " +
          "#{@nominatim_response}"
      end
      self.longitude = response['lon'].to_f
      if @longitude < -180.0 || @longitude > 180.0
        raise NomatimError, "Nominatim record longitude is out of range: " +
          "#{@nominatim_response}"
      end

      unless (address = response['address'])
        raise NominatimRecord, "Nominatim record does not contain an " +
          "address: #{@nominatim_response}"
      end

      self.country = address['country']
      self.city = address['city'] || address['town'] ||
        address['village'] || ''
      self.street = address['road'] || ''
      self.number = address['number'] || ''
      self.zip_code = address['postcode'] || ''
    end

  end

end

