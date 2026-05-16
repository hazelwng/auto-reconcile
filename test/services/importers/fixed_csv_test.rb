require "test_helper"

module Importers
  class FixedCsvTest < ActiveSupport::TestCase
    setup do
      @bank_batch = import_batches(:queued_bank)
      @invoice_batch = import_batches(:queued_invoices)
    end

    test "bank kind: creates BankTransaction + ReconcilableItem with parsed fields" do
      attach_csv(@bank_batch, <<~CSV)
        external_id,posted_date,amount,txn_type,counterparty,memo,description
        b-001,2026-04-01,1234.56,debit,Acme,Invoice 7,Acme payment
      CSV

      assert_difference -> { BankTransaction.count } => 1,
                        -> { ReconcilableItem.count } => 1 do
        FixedCsv.new(@bank_batch).call
      end

      ri = ReconcilableItem.order(:id).last
      assert_equal 123_456, ri.amount_cents
      assert_equal "AUD", ri.amount_currency
      assert_equal Date.new(2026, 4, 1), ri.occurred_on
      assert_equal "b-001", ri.external_id
      assert_equal "unmatched", ri.status

      txn = ri.item
      assert_instance_of BankTransaction, txn
      assert_equal "debit", txn.txn_type
      assert_equal "Acme", txn.counterparty
      assert_equal "Invoice 7", txn.memo

      @bank_batch.reload
      assert_equal "complete", @bank_batch.status
      assert_equal 1, @bank_batch.success_count
    end

    test "accounting kind: creates Invoice + ReconcilableItem with parsed fields" do
      attach_csv(@invoice_batch, <<~CSV)
        external_id,invoice_number,issue_date,due_date,amount,status,payer,notes,description
        i-001,INV-1001,2026-04-01,2026-05-01,500.00,open,Acme,first invoice,Acme inv
      CSV

      assert_difference -> { Invoice.count } => 1,
                        -> { ReconcilableItem.count } => 1 do
        FixedCsv.new(@invoice_batch).call
      end

      ri = ReconcilableItem.order(:id).last
      assert_equal 50_000, ri.amount_cents
      assert_equal "AUD", ri.amount_currency
      assert_equal Date.new(2026, 4, 1), ri.occurred_on

      inv = ri.item
      assert_instance_of Invoice, inv
      assert_equal "INV-1001", inv.invoice_number
      assert_equal Date.new(2026, 5, 1), inv.due_date
      assert_equal "open", inv.status
      assert_equal "Acme", inv.payer
    end

    test "amount parsing handles thousands separators and currency symbol" do
      attach_csv(@bank_batch, <<~CSV)
        external_id,posted_date,amount,txn_type
        b-001,2026-04-01,"$1,234.56",debit
        b-002,2026-04-02,"2,000",credit
      CSV

      FixedCsv.new(@bank_batch).call

      amounts = ReconcilableItem.order(:id).pluck(:amount_cents)
      assert_equal [ 123_456, 200_000 ], amounts
    end

    test "row currency overrides data_source currency when present" do
      attach_csv(@bank_batch, <<~CSV)
        external_id,posted_date,amount,txn_type,currency
        b-001,2026-04-01,100.00,debit,usd
      CSV

      FixedCsv.new(@bank_batch).call

      assert_equal "USD", ReconcilableItem.order(:id).last.amount_currency
    end

    test "rerunning the same CSV bumps duplicate_count, not success_count" do
      csv = <<~CSV
        external_id,posted_date,amount,txn_type
        b-001,2026-04-01,100.00,debit
        b-002,2026-04-02,200.00,credit
      CSV

      attach_csv(@bank_batch, csv)
      FixedCsv.new(@bank_batch).call
      @bank_batch.reload
      assert_equal 2, @bank_batch.success_count
      assert_equal 0, @bank_batch.duplicate_count

      assert_no_difference [ "BankTransaction.count", "ReconcilableItem.count" ] do
        FixedCsv.new(@bank_batch).call
      end

      @bank_batch.reload
      assert_equal 0, @bank_batch.success_count
      assert_equal 2, @bank_batch.duplicate_count
    end

    test "unsupported data_source kind records row-level error and continues" do
      @bank_batch.data_source.update!(kind: "payment_processor")
      attach_csv(@bank_batch, <<~CSV)
        external_id,posted_date,amount,txn_type
        x-001,2026-04-01,10.00,debit
      CSV

      FixedCsv.new(@bank_batch).call

      @bank_batch.reload
      # Row-level error -> batch still completes; ArgumentError is logged per-row.
      assert_equal "complete", @bank_batch.status
      assert_equal 0, @bank_batch.success_count
      assert_equal 1, @bank_batch.error_count
      assert_equal 1, @bank_batch.error_log.length
      assert_match(/ArgumentError/, @bank_batch.error_log.first["error"])
    end

    test "header whitespace and case do not break parsing" do
      attach_csv(@bank_batch, <<~CSV)
        External_ID, Posted_Date , AMOUNT,TXN_TYPE
        b-001,2026-04-01,10.00,credit
      CSV

      FixedCsv.new(@bank_batch).call

      @bank_batch.reload
      assert_equal 1, @bank_batch.success_count
      assert_equal "b-001", ReconcilableItem.order(:id).last.external_id
    end

    private

    def attach_csv(batch, content)
      batch.source_file.attach(
        io: StringIO.new(content),
        filename: "import.csv",
        content_type: "text/csv"
      )
    end
  end
end
