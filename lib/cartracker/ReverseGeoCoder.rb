#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ReverseGeoCoder.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'net/http'
require 'uri'
require 'json'

require 'perobs'

require 'cartracker/version'
require 'cartracker/NominatimRecord'
require 'cartracker/GeoGridStore'

module CarTracker

  class ReverseGeoCoder

    def initialize(store)
      @store = store
      unless @store['ReverseGeoCoderCache']
        @store['ReverseGeoCoderCache'] = @store.new(GeoGridStore)
      end
      @geo_coder = @store['ReverseGeoCoderCache']
      @last_request_timestamp = nil
    end

    def map_to_address(latitude, longitude)
      if (record = @geo_coder.look_up(latitude, longitude, 200))
        return record
      end

      return nil
      answer = request_from_nominatim(latitude, longitude)
      @geo_coder.add(answer)
    end

    def request_from_nominatim(latitude, longitude)
      # Implement a rate limit of not more than 1 request per second according
      # to nominatim usage guidelines.
      if @last_request_timestamp && @last_request_timestamp > Time.now - 1.0
        sleep(1)
      end
      @last_request_timestamp = Time.now

      args = "format=json&lat=#{latitude}&lon=#{longitude}"
      request_header = {
        'Accept' => 'application/json',
        'User-Agent' => "CarTracker/#{VERSION}"
      }
      uri = URI("https://nominatim.openstreetmap.org/reverse?#{args}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Get.new(uri, request_header)

      http.request(request).body
    end

  end

end

