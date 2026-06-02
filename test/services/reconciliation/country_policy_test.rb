require "test_helper"

module Reconciliation
  class CountryPolicyTest < ActiveSupport::TestCase
    test "resolves workspace country code to a policy object" do
      assert_instance_of CountryPolicies::AustraliaPolicy, CountryPolicy.for("AU")
      assert_instance_of CountryPolicies::JapanPolicy, CountryPolicy.for("jp")
    end

    test "keeps current matching tolerances in the default policy" do
      policy = CountryPolicies::DefaultPolicy.new

      assert_equal "exact", policy.exact_tolerances.fetch(:method)
      assert_equal 0, policy.exact_tolerances.fetch(:amount_cents)
      assert_equal 7, policy.exact_tolerances.fetch(:bank_date_window_end_days)

      assert_equal "heuristic", policy.heuristic_tolerances.fetch(:method)
      assert_equal 1, policy.heuristic_tolerances.fetch(:amount_cents)
      assert_equal(-2, policy.heuristic_tolerances.fetch(:bank_date_window_start_days))
      assert_equal 14, policy.heuristic_tolerances.fetch(:bank_date_window_end_days)
    end

    test "default policy extracts references but opts out of party scoring" do
      policy = CountryPolicies::DefaultPolicy.new

      assert_equal "acmeptyltd", policy.normalize_party_name("Acme Pty Ltd")
      assert_equal [ "INV-AU-001" ], policy.reference_tokens("Payment INV-AU-001")
      assert_equal [ "1001" ], policy.reference_tokens("Invoice 1001")
      assert_equal [ "1001" ], policy.reference_tokens("Ref: 1001")
      assert_nil policy.party_match_score(invoice: fake_invoice(payer: "Acme"), bank_transaction: fake_bank(counterparty: "Acme"))
    end

    test "australia policy strips legal suffixes for party scoring" do
      policy = CountryPolicies::AustraliaPolicy.new

      assert_equal 1.0, policy.party_match_score(
        invoice: fake_invoice(payer: "Acme Pty Ltd"),
        bank_transaction: fake_bank(counterparty: "ACME PTY LTD")
      )
      assert_equal [ "INV-AU-001" ], policy.reference_tokens("Payment INV-AU-001")
      assert_equal 0.0, policy.party_match_score(
        invoice: fake_invoice(payer: "Acme Pty Ltd"),
        bank_transaction: fake_bank(counterparty: "Beta Pty Ltd")
      )
    end

    test "japan policy compares invoice kana with bank counterparty kana" do
      policy = CountryPolicies::JapanPolicy.new

      assert_equal 1.0, policy.party_match_score(
        invoice: fake_invoice(payer: "株式会社山田商事", payer_kana: "ヤマダショウジ"),
        bank_transaction: fake_bank(counterparty: "ﾔﾏﾀﾞｼﾖｳｼﾞ")
      )
      assert_equal [ "INV-JP-001" ], policy.reference_tokens("振込 INV-JP-001")
      assert_equal 0.0, policy.party_match_score(
        invoice: fake_invoice(payer: "株式会社山田商事", payer_kana: "ヤマダショウジ"),
        bank_transaction: fake_bank(counterparty: "タナカシヨウジ")
      )
      assert_equal 0.0, policy.party_match_score(
        invoice: fake_invoice(payer: "株式会社山田商事", payer_kana: nil),
        bank_transaction: fake_bank(counterparty: "ﾔﾏﾀﾞｼﾖｳｼﾞ")
      )
    end

    private

    FakeInvoice = Struct.new(:payer, :payer_kana, :invoice_number, keyword_init: true)
    FakeBank = Struct.new(:counterparty, :memo, keyword_init: true)

    def fake_invoice(...)
      FakeInvoice.new(...)
    end

    def fake_bank(...)
      FakeBank.new(...)
    end
  end
end
