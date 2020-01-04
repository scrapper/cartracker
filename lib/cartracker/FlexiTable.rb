#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = FlexiTable.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

module CarTracker

  class FlexiTable

    class Attributes

      attr_accessor :min_terminal_width, :halign

      def initialize(attrs = {})
        @min_terminal_width = nil
        @halign = nil
        @width = nil
        @format = nil
        @label = nil

        attrs.each do |name, value|
          ivar_name = '@' + name.to_s
          unless instance_variable_defined?(ivar_name)
            Log.fatal "Unsupported attribute #{name}"
          end
          instance_variable_set(ivar_name, value)
        end
      end

      def [](name)
        ivar_name = '@' + name.to_s
        return nil unless instance_variable_defined?(ivar_name)

        instance_variable_get(ivar_name)
      end

    end

    class Cell

      def initialize(table, row, content, attributes)
        @table = table
        @row = row
        @content = content
        @value = nil
        @printable_content = nil
        @attributes = attributes

        @column_index = nil
        @row_index = nil
      end

      def min_terminal_width
        eval_content
        @printable_content.length
      end

      def set_indicies(col_idx, row_idx)
        @column_index = col_idx
        @row_index = row_idx
      end

      def value
        eval_content
        @value
      end

      def to_s
        unless @column_index
          raise "Cell #{@content.inspect} has no column index"
        end
        eval_content
        s = @printable_content

        width = get_attribute(:min_terminal_width)
        case get_attribute(:halign)
        when :left, nil
          s + ' ' * (width - s.length)
        when :right
          ' ' * (width - s.length) + s
        when :center
          w = width - s.length
          left_padding = w / 2
          right_padding = w / 2 + w % 2
          ' ' * left_padding + s + ' ' * right_padding
        else
          raise "Unknown alignment"
        end
      end

      private

      def get_attribute(name)
        @attributes[name] ||
          @row.attributes[name] ||
          (@table.column_attributes[@column_index] ?
           @table.column_attributes[@column_index][name] : nil)
      end

      def eval_content
        unless @printable_content
          if @row.is_header?
            @printable_content = @content.to_s
          else
            format = get_attribute(:format)
            if @content.respond_to?('call')
              @value = @content.call
            else
              @value = @content
            end
            @printable_content = format ?
              format.call(@value.to_s) : @value.to_s
          end
        end
      end

    end

    class Row < Array

      attr_reader :attributes

      def initialize(table, section)
        @table = table
        @section = section
        @attributes = Attributes.new
        super()
      end

      def cell(content, attributes)
        c = Cell.new(@table, self, content, attributes)
        self << c
        c
      end

      def set_indicies(col_idx, row_idx)
        @index = row_idx
        self[col_idx].set_indicies(col_idx, row_idx)
      end

      def set_row_attributes(attributes)
        @attributes = Attributes.new(attributes)
      end

      def is_header?
        @table.is_header?(self)
      end

      def to_s
        s = ''
        frame = @table.frame

        s << '|' if frame
        s << join(frame ? '|' : ' ')
        s << '|' if frame

        s
      end

    end

    attr_reader :frame, :column_attributes

    def initialize(&block)
      @head_rows = []
      @body_rows = []
      @foot_rows = []
      @column_count = 0

      @current_section = :body
      @current_row = nil

      @frame = true

      @column_attributes = []

      instance_eval(&block) if block_given?
    end

    def head
      @current_section = :head
    end

    def body
      @current_section = :body
      @current_row = nil
    end

    def foot
      @current_section = :foot
      @current_row = nil
    end

    def new_row
      if @current_row && @head_rows[0] &&
         @current_row.length != @head_rows[0].length
        Log.fatal "Row has #{@current_row.length} cells instead of " +
                  "#{@head_rows[0].length} cells in head row."
      end
      @current_row = nil
    end

    def cell(content, attributes = {})
      if @current_row.nil?
        case @current_section
        when :head
          @head_rows
        when :body
          @body_rows
        when :foot
          @foot_rows
        else
          raise "Unknown section #{@current_section}"
        end << (@current_row = Row.new(self, @current_section))
      end
      @current_row.cell(content, attributes)
    end

    def row(cells, attributes = {})
      cells.each { |c| cell(c) }
      set_row_attributes(attributes)
      new_row
    end

    def set_column_attributes(col_attributes)
      col_attributes.each.with_index do |ca, idx|
        @column_attributes[idx] = Attributes.new(ca)
      end
    end

    def set_row_attributes(row_attributes)
      unless @current_row
        raise "No current row. Use after first cell definition but before " +
              "new_row call."
      end
      @current_row.set_row_attributes(row_attributes)
    end

    def is_header?(row)
      @head_rows.include?(row)
    end

    def enable_frame(enabled)
      @frame = enabled
    end

    def to_s
      index_table
      calc_terminal_columns

      s = frame_line_to_s
      s << rows_to_s(@head_rows)
      s << frame_line_to_s unless @head_rows.empty?
      s << rows_to_s(@body_rows)
      s << frame_line_to_s unless @body_rows.empty?
      s << rows_to_s(@foot_rows)
      s << frame_line_to_s unless @foot_rows.empty?

      s
    end

    # Return the index of the next cell to be added.
    def column_label_to_idx(label)
      @column_attributes.each_with_index do |attr, idx|
        return idx if attr['label'] == label
      end

      nil
    end

    def iterate(start_col, start_row, end_col, end_row)
      start_col_idx = check_and_fix_col_idx('Start column', start_col)
      start_row_idx = check_and_fix_body_row_idx('Start row', start_row)
      end_col_idx = check_and_fix_col_idx('End column', end_col)
      end_row_idx = check_and_fix_body_row_idx('End row', end_row)

      start_col_idx.upto(end_col_idx) do |col_idx|
        start_row_idx.upto(end_row_idx) do |row_idx|
          yield(@body_rows[row_idx][col_idx].value)
        end
      end
    end

    def value(col, row)
      col_idx = check_and_fix_col_idx(col)
      row_idx = check_and_fix_body_row_idx(row)

      @body_rows[row_idx][col_idx].value
    end

    def foot_value(col, row)
      col_idx = check_and_fix_col_idx('Column', col)
      row_idx = check_and_fix_foot_row_idx('Row', row)

      @foot_rows[row_idx][col_idx].value
    end

    def sum(start_col, start_row, end_col, end_row)
      sum = 0
      iterate(start_col, start_row, end_col, end_row) do |v|
        sum += v
      end

      sum
    end

    def arithmetic_mean(start_col, start_row, end_col, end_row)
      sum = 0
      i = 0
      iterate(start_col, start_row, end_col, end_row) do |v|
        sum += v
        i += 1
      end

      sum / i.to_f
    end

    def index_table
      @column_count = (@head_rows[0] || @body_rows[0]).length

      @column_count.times do |i|
        index_table_rows(i, @head_rows)
        index_table_rows(i, @body_rows)
        index_table_rows(i, @foot_rows)
      end
    end

    def index_table_rows(col_idx, rows)
      rows.each.with_index do |r, row_idx|
        r.set_indicies(col_idx, row_idx)
      end
    end

    def calc_terminal_columns
      @column_count.times do |i|
        col_mtw = nil

        col_mtw = calc_section_teminal_columns(i, col_mtw, @head_rows)
        col_mtw = calc_section_teminal_columns(i, col_mtw, @body_rows)
        col_mtw = calc_section_teminal_columns(i, col_mtw, @foot_rows)

        @column_attributes[i] = Attributes.new unless @column_attributes[i]
        @column_attributes[i].min_terminal_width = col_mtw
      end
    end

    def calc_section_teminal_columns(col_idx, col_mtw, rows)
      rows.each do |r|
        if r[col_idx].nil?
          raise ArgumentError, "Not all rows have same number of cells"
        end

        mtw = r[col_idx].min_terminal_width
        if col_mtw.nil? || col_mtw < mtw
          col_mtw = mtw
        end
      end

      col_mtw
    end

    def rows_to_s(x_rows)
      x_rows.empty? ? '' : (x_rows.map { |r| r.to_s}.join("\n") + "\n")
    end

    def frame_line_to_s
      return '' unless @frame
      s = '+'
      @column_attributes.each do |c|
        s += '-' * c.min_terminal_width + '+'
      end
      s + "\n"
    end

    private

    def check_and_fix_col_idx(name, col)
      col_idx = col.is_a?(Symbol) ? column_label_to_idx(col) : col

      col_idx = @column_count + col_idx if col_idx < 0

      max = [@column_count - 1, col_idx].min
      if col_idx > max
        raise ArgumentError, "#{name} index (#{col_idx}) must " +
          "be smaller than #{max}"
      end

      col_idx
    end

    def check_and_fix_body_row_idx(name, row)
      row_idx = row

      row_idx = @body_rows.length + row_idx if row_idx < 0

      if row_idx >= @body_rows.length
        raise ArgumentError, "#{name} index (#{row_idx}) must " +
          "be smaller than #{@body_rows.length}"
      end

      row_idx
    end

    def check_and_fix_foot_row_idx(name, row)
      row_idx = row

      row_idx = @foot_rows.length + row_idx if row_idx < 0

      if row_idx >= @foot_rows.length
        raise ArgumentError, "#{name} index (#{row_idx}) must " +
          "be smaller than #{@foot_rows.length}"
      end

      row_idx
    end

  end

end

