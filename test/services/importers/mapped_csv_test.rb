require "test_helper"

module Importers
  class MappedCsvTest < ActiveSupport::TestCase
    setup do
      @bank_batch = import_batches(:queued_bank)
      @invoice_batch = import_batches(:queued_invoices)
    end

    test "bank kind: single amount + txn_type mapping creates BankTransaction + ReconcilableItem" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id"  => "Reference",
        "amount"       => "Net Amount",
        "txn_type"     => "Type",
        "posted_date"  => "Date",
        "counterparty" => "Description",
        "memo"         => "Notes",
        "currency"     => "CCY"
      })
      attach_csv(@bank_batch, <<~CSV)
        Reference,Date,Net Amount,Type,Description,Notes,CCY
        ref-1,2026-04-01,1234.56,debit,Acme,note1,USD
      CSV

      assert_difference -> { BankTransaction.count } => 1,
                        -> { ReconcilableItem.count } => 1 do
        MappedCsv.new(@bank_batch).call
      end

      ri = ReconcilableItem.order(:id).last
      assert_equal(-123_456, ri.amount_cents)
      assert_equal "USD", ri.amount_currency
      assert_equal Date.new(2026, 4, 1), ri.occurred_on
      assert_equal "ref-1", ri.external_id

      txn = ri.item
      assert_equal "debit", txn.txn_type
      assert_equal "Acme", txn.counterparty
      assert_equal "note1", txn.memo

      @bank_batch.reload
      assert_equal "complete", @bank_batch.status
      assert_equal 1, @bank_batch.success_count
    end

    test "bank kind: Format A signed amount with no txn_type column derives txn_type from sign" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id" => "Ref",
        "amount"      => "Amount",
        "posted_date" => "Date"
        # NOTE: no txn_type mapping — sign of `amount` is authoritative.
      })
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date,Amount
        r-credit,2026-04-01,100.00
        r-debit,2026-04-02,-250.00
      CSV

      MappedCsv.new(@bank_batch).call

      rows = ReconcilableItem.order(:id).pluck(:external_id, :amount_cents).to_h
      assert_equal({ "r-credit" => 10_000, "r-debit" => -25_000 }, rows)

      types = BankTransaction.order(:id).pluck(:txn_type)
      assert_equal [ "credit", "debit" ], types

      @bank_batch.reload
      assert_equal 2, @bank_batch.success_count
      assert_equal 0, @bank_batch.error_count
    end

    test "bank kind: two-column debit/credit mapping computes signed amount and derives txn_type" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id"   => "Ref",
        "posted_date"   => "Date",
        "amount_debit"  => "Withdrawal",
        "amount_credit" => "Deposit"
      })
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date,Withdrawal,Deposit
        r-credit,2026-04-01,,500.00
        r-debit,2026-04-02,250.00,
      CSV

      MappedCsv.new(@bank_batch).call

      rows = ReconcilableItem.order(:id).pluck(:external_id, :amount_cents).to_h
      assert_equal({ "r-credit" => 50_000, "r-debit" => -25_000 }, rows)

      types = BankTransaction.order(:id).pluck(:txn_type)
      assert_equal [ "credit", "debit" ], types

      @bank_batch.reload
      assert_equal 2, @bank_batch.success_count
      assert_equal 0, @bank_batch.error_count
    end

    test "bank kind: row with both debit and credit populated is a row-level error" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id"   => "Ref",
        "posted_date"   => "Date",
        "amount_debit"  => "Withdrawal",
        "amount_credit" => "Deposit"
      })
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date,Withdrawal,Deposit
        r-bad,2026-04-01,100.00,200.00
      CSV

      MappedCsv.new(@bank_batch).call

      @bank_batch.reload
      assert_equal 0, @bank_batch.success_count
      assert_equal 1, @bank_batch.error_count
      assert_match(/both debit and credit/, @bank_batch.error_log.first["error"])
    end

    test "bank kind: row with neither debit nor credit is a row-level error" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id"   => "Ref",
        "posted_date"   => "Date",
        "amount_debit"  => "Withdrawal",
        "amount_credit" => "Deposit"
      })
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date,Withdrawal,Deposit
        r-empty,2026-04-01,,
      CSV

      MappedCsv.new(@bank_batch).call

      @bank_batch.reload
      assert_equal 1, @bank_batch.error_count
      assert_match(/neither debit nor credit/, @bank_batch.error_log.first["error"])
    end

    test "accounting kind: mapped headers create Invoice + ReconcilableItem" do
      @invoice_batch.data_source.update!(schema_mapping: {
        "external_id"    => "InvoiceID",
        "invoice_number" => "Number",
        "issue_date"     => "IssuedOn",
        "due_date"       => "DueOn",
        "amount"         => "Total",
        "payer"          => "Customer",
        "status"         => "Status"
      })
      attach_csv(@invoice_batch, <<~CSV)
        InvoiceID,Number,IssuedOn,DueOn,Total,Customer,Status
        inv-1,INV-9001,2026-04-01,2026-05-01,500.00,Acme,open
      CSV

      assert_difference -> { Invoice.count } => 1,
                        -> { ReconcilableItem.count } => 1 do
        MappedCsv.new(@invoice_batch).call
      end

      ri = ReconcilableItem.order(:id).last
      assert_equal 50_000, ri.amount_cents
      assert_equal Date.new(2026, 4, 1), ri.occurred_on

      inv = ri.item
      assert_equal "INV-9001", inv.invoice_number
      assert_equal Date.new(2026, 5, 1), inv.due_date
      assert_equal "Acme", inv.payer
      assert_equal "open", inv.status
    end

    test "empty schema_mapping raises and marks batch failed" do
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date,Amount,Type
        r-1,2026-04-01,10.00,credit
      CSV
      # schema_mapping defaults to {}; do not set it.

      MappedCsv.new(@bank_batch).call

      @bank_batch.reload
      # validate_mapping! raises ArgumentError per-row -> row-level error.
      assert_equal 1, @bank_batch.error_count
      assert_match(/schema_mapping is empty/, @bank_batch.error_log.first["error"])
    end

    test "bank mapping without amount/txn_type pair or debit/credit pair errors per row" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id" => "Ref",
        "posted_date" => "Date"
        # missing both (amount + txn_type) and (amount_debit/credit)
      })
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date
        r-1,2026-04-01
      CSV

      MappedCsv.new(@bank_batch).call

      @bank_batch.reload
      assert_equal 1, @bank_batch.error_count
      assert_match(/amount.*txn_type.*amount_debit/m, @bank_batch.error_log.first["error"])
    end

    test "rerunning the same CSV bumps duplicate_count, not success_count" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id" => "Ref",
        "amount"      => "Amount",
        "txn_type"    => "Type",
        "posted_date" => "Date"
      })
      csv = <<~CSV
        Ref,Date,Amount,Type
        r-001,2026-04-01,100.00,debit
        r-002,2026-04-02,200.00,credit
      CSV

      attach_csv(@bank_batch, csv)
      MappedCsv.new(@bank_batch).call
      @bank_batch.reload
      assert_equal 2, @bank_batch.success_count

      assert_no_difference [ "BankTransaction.count", "ReconcilableItem.count" ] do
        MappedCsv.new(@bank_batch).call
      end

      @bank_batch.reload
      assert_equal 2, @bank_batch.duplicate_count
      assert_equal 0, @bank_batch.success_count
    end

    test "row currency overrides data_source currency when present in mapping" do
      @bank_batch.data_source.update!(schema_mapping: {
        "external_id" => "Ref",
        "amount"      => "Amount",
        "txn_type"    => "Type",
        "posted_date" => "Date",
        "currency"    => "CCY"
      })
      attach_csv(@bank_batch, <<~CSV)
        Ref,Date,Amount,Type,CCY
        r-1,2026-04-01,100.00,credit,usd
      CSV

      MappedCsv.new(@bank_batch).call

      assert_equal "USD", ReconcilableItem.order(:id).last.amount_currency
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
