module Importers
  class Base
    BATCH_SIZE = 500

    def initialize(batch)
      @batch = batch
    end

    def call
      start!

      iter_rows(@batch).each_with_index do |row, idx|
        row_number = idx + 1
        @batch.row_count += 1
        @batch.processed_count += 1

        begin
          import_row(@batch, row, row_number)
          @batch.success_count += 1
        rescue ActiveRecord::RecordNotUnique
          @batch.duplicate_count += 1
        rescue ActiveRecord::RecordInvalid => e
          if duplicate_external_id?(e.record)
            @batch.duplicate_count += 1
          else
            @batch.error_count += 1
            append_error(row_number, row, e)
          end
        rescue => e
          @batch.error_count += 1
          append_error(row_number, row, e)
        end

        @batch.save! if (@batch.processed_count % BATCH_SIZE).zero?
      end

      finish!(:complete)
    rescue => e
      @batch.error_message = "#{e.class}: #{e.message}" if @batch.respond_to?(:error_message=)
      append_error(nil, nil, e)
      finish!(:failed)
      raise
    end

    private

    def iter_rows(batch)
      raise NotImplementedError, "#{self.class} must implement #iter_rows"
    end

    def import_row(batch, row, row_number)
      raise NotImplementedError, "#{self.class} must implement #import_row"
    end

    def start!
      @batch.update!(
        status: "processing",
        started_at: Time.current,
        completed_at: nil,
        row_count: 0,
        processed_count: 0,
        success_count: 0,
        error_count: 0,
        duplicate_count: 0,
        error_log: []
      )
    end

    def finish!(outcome)
      @batch.status = outcome.to_s
      @batch.completed_at = Time.current
      @batch.save!
    end

    def append_error(row_number, row, error)
      log = normalize_error_log(@batch.error_log)
      log << {
        row_number: row_number,
        external_id: row.is_a?(Hash) ? row[:external_id] || row["external_id"] : nil,
        error: "#{error.class}: #{error.message}",
        raw_row: row
      }
      @batch.error_log = log
    end

    def normalize_error_log(value)
      case value
      when Array then value
      else []
      end
    end

    def duplicate_external_id?(record)
      return false unless record.is_a?(ReconcilableItem)
      record.errors.where(:external_id_hash, :taken).any?
    end
  end
end
