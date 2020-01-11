#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = TimeUtils.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019, 2020 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

module CarTracker

  module TimeUtils

    def TimeUtils::secs2hms(secs)
      secs = secs.to_i
      s = secs % 60
      mins = secs / 60
      m = mins % 60
      h = mins / 60
      "#{h}:#{'%02d' % m}:#{'%02d' % s}"
    end

    def TimeUtils::mins2dhm(mins)
      mins = mins.to_i
      m = mins % 60
      h = mins / 60
      d = mins / (60 * 60)
      "#{d}:#{'%02d' % h}:#{'%02d' % m}"
    end

  end

end
