require "test_helper"

module Reconciliation
  class MultiCountryHeuristicTest < ActiveSupport::TestCase
    setup do
      @user = users(:hazel)
    end

    test "australia heuristic match is corroborated by normalized party and reference" do
      setup_context(country_code: "AU", currency: "AUD")
      invoice_item = make_invoice(
        external: "au-inv-1",
        invoice_number: "INV-AU-001",
        payer: "Acme Pty Ltd",
        amount_cents: 125_000,
        occurred_on: Date.new(2026, 4, 1)
      )
      bank_item = make_bank(
        external: "au-bank-1",
        counterparty: "ACME PTY LTD",
        memo: "Payment INV-AU-001",
        amount_cents: 125_001,
        occurred_on: Date.new(2026, 4, 2)
      )

      stats = Matchers::ExactMatcher.new(@run).call

      assert_equal 1, stats[:matches_created]
      assert_equal "proposed", invoice_item.reload.status
      assert_equal "proposed", bank_item.reload.status

      match = Match.last
      assert_equal "heuristic", match.method
      assert_match(/latin-normalized party match/, match.reasoning)
      assert_match(/reference INV-AU-001/, match.reasoning)
    end

    test "japan heuristic match is corroborated by kana party and reference" do
      setup_context(country_code: "JP", currency: "JPY")
      invoice_item = make_invoice(
        external: "jp-inv-1",
        invoice_number: "INV-JP-001",
        payer: "株式会社山田商事",
        payer_kana: "ヤマダショウジ",
        amount_cents: 11_000_000,
        occurred_on: Date.new(2026, 4, 1)
      )
      bank_item = make_bank(
        external: "jp-bank-1",
        counterparty: "ﾔﾏﾀﾞｼﾖｳｼﾞ",
        memo: "振込 INV-JP-001",
        amount_cents: 11_000_001,
        occurred_on: Date.new(2026, 4, 2)
      )

      stats = Matchers::ExactMatcher.new(@run).call

      assert_equal 1, stats[:matches_created]
      assert_equal "proposed", invoice_item.reload.status
      assert_equal "proposed", bank_item.reload.status

      match = Match.last
      assert_equal "heuristic", match.method
      assert_in_delta 0.85, match.confidence.to_f, 1e-6
      assert_match(/kana-normalized party match/, match.reasoning)
      assert_match(/reference INV-JP-001/, match.reasoning)
    end

    test "australia heuristic candidate without party or reference evidence stays unresolved" do
      setup_context(country_code: "AU", currency: "AUD")
      invoice_item = make_invoice(
        external: "au-inv-negative",
        invoice_number: "INV-AU-404",
        payer: "Acme Pty Ltd",
        amount_cents: 50_000,
        occurred_on: Date.new(2026, 4, 1)
      )
      bank_item = make_bank(
        external: "au-bank-negative",
        counterparty: "Beta Pty Ltd",
        memo: "Payment",
        amount_cents: 50_001,
        occurred_on: Date.new(2026, 4, 2)
      )

      stats = Matchers::ExactMatcher.new(@run).call

      assert_equal 0, stats[:matches_created]
      assert_equal 1, stats[:source_a_unmatched]
      assert_equal "unmatched", invoice_item.reload.status
      assert_equal "unmatched", bank_item.reload.status
    end

    test "japan heuristic candidate with different kana and no reference stays unresolved" do
      setup_context(country_code: "JP", currency: "JPY")
      invoice_item = make_invoice(
        external: "jp-inv-negative",
        invoice_number: "INV-JP-404",
        payer: "株式会社山田商事",
        payer_kana: "ヤマダショウジ",
        amount_cents: 22_000_000,
        occurred_on: Date.new(2026, 4, 1)
      )
      bank_item = make_bank(
        external: "jp-bank-negative",
        counterparty: "タナカシヨウジ",
        memo: "振込",
        amount_cents: 22_000_001,
        occurred_on: Date.new(2026, 4, 2)
      )

      stats = Matchers::ExactMatcher.new(@run).call

      assert_equal 0, stats[:matches_created]
      assert_equal 1, stats[:source_a_unmatched]
      assert_equal "unmatched", invoice_item.reload.status
      assert_equal "unmatched", bank_item.reload.status
    end

    private

    def setup_context(country_code:, currency:)
      @workspace = Workspace.create!(
        name: "#{country_code} Co",
        slug: "#{country_code.downcase}-co-#{SecureRandom.hex(4)}",
        base_currency: currency,
        country_code: country_code
      )
      @source_a = DataSource.create!(workspace: @workspace, name: "#{country_code} Invoices", kind: "accounting", currency: currency)
      @source_b = DataSource.create!(workspace: @workspace, name: "#{country_code} Bank", kind: "bank", currency: currency)
      @batch_a = ImportBatch.create!(data_source: @source_a, user: @user, status: "queued")
      @batch_b = ImportBatch.create!(data_source: @source_b, user: @user, status: "queued")
      @run = ReconciliationRun.create!(
        workspace: @workspace,
        triggered_by_user: @user,
        source_a: @source_a,
        source_b: @source_b,
        date_range_start: Date.new(2026, 4, 1),
        date_range_end: Date.new(2026, 4, 30),
        status: "running"
      )
    end

    def make_invoice(external:, invoice_number:, payer:, amount_cents:, occurred_on:, payer_kana: nil)
      invoice = Invoice.create!(
        workspace: @workspace,
        invoice_number: invoice_number,
        issue_date: occurred_on,
        total_cents: amount_cents.abs,
        currency: @source_a.currency,
        status: "open",
        payer: payer,
        payer_kana: payer_kana
      )
      ReconcilableItem.create!(
        workspace: @workspace,
        data_source: @source_a,
        import_batch: @batch_a,
        item: invoice,
        amount_cents: amount_cents,
        amount_currency: @source_a.currency,
        occurred_on: occurred_on,
        external_id: external,
        external_id_hash: Digest::SHA256.hexdigest("#{@source_a.id}:#{external}"),
        status: "unmatched"
      )
    end

    def make_bank(external:, counterparty:, memo:, amount_cents:, occurred_on:)
      bank = BankTransaction.create!(
        workspace: @workspace,
        posted_date: occurred_on,
        txn_type: amount_cents >= 0 ? "credit" : "debit",
        counterparty: counterparty,
        memo: memo
      )
      ReconcilableItem.create!(
        workspace: @workspace,
        data_source: @source_b,
        import_batch: @batch_b,
        item: bank,
        amount_cents: amount_cents,
        amount_currency: @source_b.currency,
        occurred_on: occurred_on,
        description: memo,
        external_id: external,
        external_id_hash: Digest::SHA256.hexdigest("#{@source_b.id}:#{external}"),
        status: "unmatched"
      )
    end
  end
end
