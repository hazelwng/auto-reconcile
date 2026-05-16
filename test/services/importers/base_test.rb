require "test_helper"

module Importers
  class BaseTest < ActiveSupport::TestCase
    # In-test subclass that lets each test inject its own rows + per-row behavior.
    class StubImporter < Base
      def initialize(batch, rows:, row_handler:)
        super(batch)
        @rows = rows
        @row_handler = row_handler
      end

      private

      def iter_rows(_batch)
        @rows
      end

      def import_row(batch, row, row_number)
        @row_handler.call(batch, row, row_number)
      end
    end

    setup do
      @batch = import_batches(:queued_bank)
    end

    test "happy path: transitions queued -> processing -> complete and tallies counters" do
      rows = [ { "external_id" => "a" }, { "external_id" => "b" }, { "external_id" => "c" } ]
      handler = ->(_batch, _row, _n) { } # all succeed

      StubImporter.new(@batch, rows: rows, row_handler: handler).call

      @batch.reload
      assert_equal "complete", @batch.status
      assert_equal 3, @batch.row_count
      assert_equal 3, @batch.processed_count
      assert_equal 3, @batch.success_count
      assert_equal 0, @batch.error_count
      assert_equal 0, @batch.duplicate_count
      assert_equal [], @batch.error_log
      assert_not_nil @batch.started_at
      assert_not_nil @batch.completed_at
    end

    test "RecordNotUnique increments duplicate_count and skips error_log" do
      rows = [ { "external_id" => "a" }, { "external_id" => "dup" }, { "external_id" => "c" } ]
      handler = ->(_batch, row, _n) {
        raise ActiveRecord::RecordNotUnique, "dup" if row["external_id"] == "dup"
      }

      StubImporter.new(@batch, rows: rows, row_handler: handler).call

      @batch.reload
      assert_equal "complete", @batch.status
      assert_equal 2, @batch.success_count
      assert_equal 1, @batch.duplicate_count
      assert_equal 0, @batch.error_count
      assert_equal [], @batch.error_log
    end

    test "RecordInvalid with external_id_hash :taken counts as duplicate, not error" do
      rows = [ { "external_id" => "dup" } ]
      handler = ->(_batch, _row, _n) {
        # Build an unsaved ReconcilableItem with the taken-uniqueness error so the
        # `duplicate_external_id?` check matches.
        ri = ReconcilableItem.new
        ri.errors.add(:external_id_hash, :taken)
        raise ActiveRecord::RecordInvalid.new(ri)
      }

      StubImporter.new(@batch, rows: rows, row_handler: handler).call

      @batch.reload
      assert_equal 1, @batch.duplicate_count
      assert_equal 0, @batch.error_count
      assert_equal [], @batch.error_log
    end

    test "generic row error increments error_count and appends to error_log with fixed shape" do
      rows = [ { "external_id" => "boom", "amount" => "10.00" } ]
      handler = ->(_batch, _row, _n) { raise StandardError, "bad row" }

      StubImporter.new(@batch, rows: rows, row_handler: handler).call

      @batch.reload
      assert_equal "complete", @batch.status
      assert_equal 0, @batch.success_count
      assert_equal 1, @batch.error_count
      assert_equal 1, @batch.error_log.length

      entry = @batch.error_log.first.symbolize_keys
      assert_equal [ :row_number, :external_id, :error, :raw_row ].sort, entry.keys.sort
      assert_equal 1, entry[:row_number]
      assert_equal "boom", entry[:external_id]
      assert_match(/StandardError: bad row/, entry[:error])
      assert_equal({ "external_id" => "boom", "amount" => "10.00" }, entry[:raw_row])
    end

    test "iter_rows itself raising marks batch failed and re-raises" do
      failing = Class.new(Base) do
        private

        def iter_rows(_batch)
          raise RuntimeError, "csv blew up"
        end

        def import_row(_batch, _row, _row_number); end
      end

      assert_raises(RuntimeError) { failing.new(@batch).call }

      @batch.reload
      assert_equal "failed", @batch.status
      assert_not_nil @batch.completed_at
      assert_equal 1, @batch.error_log.length
      assert_match(/RuntimeError: csv blew up/, @batch.error_log.first["error"])
    end

    test "rerun resets counters and error_log (idempotent retry)" do
      # First run: 1 row, 1 error.
      StubImporter.new(@batch,
        rows: [ { "external_id" => "x" } ],
        row_handler: ->(_b, _r, _n) { raise StandardError, "first run boom" }
      ).call
      @batch.reload
      assert_equal 1, @batch.error_count

      # Second run: 2 rows, all succeed. start! should wipe everything.
      StubImporter.new(@batch,
        rows: [ { "external_id" => "a" }, { "external_id" => "b" } ],
        row_handler: ->(_b, _r, _n) { }
      ).call

      @batch.reload
      assert_equal 2, @batch.success_count
      assert_equal 0, @batch.error_count
      assert_equal 0, @batch.duplicate_count
      assert_equal [], @batch.error_log
      assert_equal "complete", @batch.status
    end
  end
end
