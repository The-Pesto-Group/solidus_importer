# frozen_string_literal: true

require 'csv'

module SolidusImporter
  ##
  # This class parse the source file and create the rows (scan). Then it asks to
  # Process Row to process each one.
  class ProcessImport
    attr_reader :importer

    def initialize(import, importer_options: nil)
      @import = import
      options = importer_options || ::SolidusImporter::Config.solidus_importer[@import.import_type.to_sym]
      @importer = options[:importer].new(options)
      @import.importer = @importer
      validate!
    end

    def process(force_scan: nil)
      return @import unless @import.created_or_failed?

      scan_required = force_scan.nil? ? @import.created? : force_scan
      @import.update(state: :processing)
      initial_context = scan_required ? scan : { success: true }
      initial_context = @importer.before_import(initial_context)
      unless @import.failed?
        rows = process_rows(initial_context)
        ending_context = @importer.after_import(initial_context)
        state = @import.state
        state = :completed if rows.zero?
        state = :failed if ending_context[:success] == false

        messages = ending_context[:messages].try(:join, ', ')

        @import.update(state: state, messages: messages)
      end
      @import
    end

    class << self
      def import_from_file(import_path, import_type, before_process_import: -> (_) {})
        import = ::SolidusImporter::Import.new(import_type: import_type)
        import.import_file = import_path
        before_process_import.(import)
        import.save!
        new(import).process
      end
    end

    private

    # NOTE: Method :scan modified from original
    def scan
      data = nil
      @import.file.open do |file_handle|
        data = CSV.parse(
          file_handle.read,
          headers: true,
          encoding: 'UTF-8',
          header_converters: ->(h) { h.strip }
        )
      end
      prepare_rows(data)
    end

    def validate_csv_format(csv_table)
      messages = []
      ::SolidusImporter.config.csv_format_validators.each do |validator|
        messages << validator.call(csv_table)
      end
      messages.compact
    end

    def prepare_rows(data)
      messages = validate_csv_format(data)
      if messages.empty?
        data.each do |row|
          @import.rows << ::SolidusImporter::Row.new(data: row.to_h)
        end
        { success: true }
      else
        @import.update(state: :failed, messages: messages.join(', '))
        { success: false, messages: messages.join(', ') }
      end
    end

    def process_rows(initial_context)
      rows = @import.rows.created_or_failed.order(id: :asc)
      rows.each do |row|
        ::SolidusImporter::ProcessRow.new(@importer, row).process(initial_context)
      end
      rows.size
    end

    def validate!
      raise ::SolidusImporter::Exception, 'Valid import entity required' if !@import || !@import.valid?
      raise ::SolidusImporter::Exception, "No importer found for #{@import.import_type} type" if !@importer
    end
  end
end
