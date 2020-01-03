#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = GeoGridStore.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019, 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'perobs'

require 'cartracker/NominatimRecord'

module CarTracker

  class GeoGridStore < PEROBS::Object

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

    def add(json)
      r = @store.new(NominatimRecord)
      r.nominatim_response = json
      begin
        r.extract_data_from_response
      rescue NominatimError => e
        return nil
      end

      lat_idx = lat_to_idx(r.latitude)
      lon_idx = lon_to_idx(r.longitude)

      unless (lat_row = @by_latitude[lat_idx.to_s])
        @by_latitude[lat_idx.to_s] = lat_row = @store.new(PEROBS::Hash)
      end
      unless (lon_row = lat_row[lon_idx.to_s])
        lat_row[lon_idx.to_s] = lon_row = @store.new(PEROBS::Array)
      end

      lon_row << r

      r
    end

    def each(&block)
      @by_latitude.each do |lat_idx, lat_row|
        lat_row.each do |lon_idx, lon_row|
          lon_row.each do |record|
            yield(record)
          end
        end
      end
    end

    def size
      i = 0
      each { |r| i += 1 }
      i
    end

    def look_up(latitude, longitude, max_distance)
      if latitude < -90.0 || latitude > 90.0
        raise ArgumentError, "latitude out of range: #{latitude}"
      end
      if longitude < -180.0 || longitude > 180.0
        raise ArgumentError, "longitude out of range: #{longitude}"
      end

      lat_idx = lat_to_idx(latitude)
      lon_idx = lon_to_idx(longitude)

      closest_record = nil
      closest_distance = nil

      (lat_idx - 1).upto(lat_idx + 1) do |lati|
        (lon_idx - 1).upto(lon_idx + 1) do |loni|
          if (lat_row = @by_latitude[lati.to_s]) &&
              (lon_row = lat_row[loni.to_s])
            lon_row.each do |record|
              d = calc_distance(latitude, longitude, record.latitude,
                                record.longitude)
              # If the record location is within max_distance meters of the
              # given location and closer than the so far closest record we
              # assign the current record as the closest record.
              if d <= max_distance &&
                  (closest_distance.nil? || closest_distance > d)
                closest_record = record
                closest_distance = d
              end
            end
          end
        end
      end

      closest_record
    end

    private

    def lat_to_idx(latitude)
      (latitude * 10).to_i
    end

    def lon_to_idx(longitude)
      (longitude * 10).to_i
    end

    # This method uses the ellipsoidal earth projected to a plane formula
    # prescribed by the FCC in 47 CFR 73.208 for distances not exceeding 475
    # km /295 miles.
    # @param p1_lat Latitude of the first point in polar degrees
    # @param p1_lon Longitude of the first point in polar degrees
    # @param p2_lat Latitude of the second point in polar degrees
    # @param p2_lon Longitude of the second point in polar degrees
    # @return Distance in meters
    def calc_distance(p1_lat, p1_lon, p2_lat, p2_lon)
      # Difference in latitude and longitude
      delta_lat = p2_lat - p1_lat
      delta_lon = p2_lon - p1_lon

      # Mean latitude
      mean_lat = (p1_lat + p2_lat) / 2

      # kilometers per degree of latitude difference
      k1 = 111.13209 - 0.56606 * cos(2 * mean_lat) +
           0.00120 * cos(4 * mean_lat)
      # kilometers per degree of longitude difference
      k2 = 111.41513 * cos(mean_lat) -
           0.09455 * cos(3 * mean_lat) +
           0.00012 * cos(5 * mean_lat)

      Math.sqrt(((k1 * delta_lat)) ** 2 + (k2 * delta_lon) ** 2) * 1000.0
    end

    def cos(deg)
      Math.cos(deg_to_rad(deg))
    end

    def deg_to_rad(deg)
      deg * Math::PI / 180
    end

  end

end

