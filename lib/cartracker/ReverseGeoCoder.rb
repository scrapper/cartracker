#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Main.rb -- CarTracker - Capture and analyze your EV telemetry.
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

require 'version'

module CarTracker

  class ReverseGeoCoder

    class Record < PEROBS::Object

      attr_persist :latitude, :longitude, :country, :city, :zip_code, :street,
        :number

      def initialize(p)
        super
      end

    end

    class GridStore < PEROBS::Object

      attr_persist :by_latitude

      def initialize(p)
        super
        restore
      end

      def restore
        unless @by_latitude
          self.by_latitude = @store.new(PEROBS::Hash)
        end
      end

      def store(record)
        lat_idx
      end

      def look_up(latitude, longitude)
      end

    end

    def initialize(store)
      @store = store
      unless @store['ReverseGeoCoderCache']
        @store['ReverseGeoCoderCache'] = @store.new(GridStore)
      end
    end

    def map_to_address(latitude, longitude)
      args = "format=json&lat=#{latitude / 1000000.0}&lon=#{longitude / 1000000.0}"
      request_header = {
        'Accept' => 'application/json',
        'User-Agent' => "CarTracker/#{VERSION}"
      }
      uri = URI("https://nominatim.openstreetmap.org/reverse?#{args}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Get.new(uri, request_header)

      answer = http.request(request)

      json = JSON.parse(http.body)
      if (address = json['address'])
        puts address.road
        puts address.city
      else
        Log.error "Response from #{uri.host} does not contain an address: #{json.inspect}"
        return nil
      end
    end

  end

  rgc = ReverseGeoCoder.new(nil)
  rgc.map_to_address(49470810, 11074698)
end

