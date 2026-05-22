require "test_helper"

module Importers
  class AutoDetectMappingTest < ActiveSupport::TestCase
    test "bank: detects canonical headers from common bank exports with high confidence" do
      result = AutoDetectMapping.new(
        headers: [ "Transaction ID", "Date", "Amount", "Type", "Currency", "Counterparty" ],
        kind: "bank"
      ).call

      assert_equal "Transaction ID", result.mapping["external_id"]
      assert_equal "Date",           result.mapping["posted_date"]
      assert_equal "Amount",         result.mapping["amount"]
      assert_equal "Type",           result.mapping["txn_type"]
      assert_equal "Currency",       result.mapping["currency"]
      assert_equal "Counterparty",   result.mapping["counterparty"]
      assert_empty result.low_confidence
      assert_empty result.unmapped_headers
    end

    test "bank: detects debit/credit split layout" do
      result = AutoDetectMapping.new(
        headers: [ "Reference", "Date", "Debit", "Credit", "CCY", "Description" ],
        kind: "bank"
      ).call

      assert_equal "Reference", result.mapping["external_id"]
      assert_equal "Debit",     result.mapping["amount_debit"]
      assert_equal "Credit",    result.mapping["amount_credit"]
      assert_equal "CCY",       result.mapping["currency"]
      assert_equal "Description", result.mapping["counterparty"]
      assert_includes result.low_confidence, "counterparty"
      assert_nil result.mapping["amount"]
    end

    test "bank: counterparty falls back to Description with low confidence when no explicit counterparty column" do
      result = AutoDetectMapping.new(
        headers: [ "Transaction ID", "Date", "Amount", "Description" ],
        kind: "bank"
      ).call

      assert_equal "Description", result.mapping["counterparty"]
      assert_includes result.low_confidence, "counterparty"
    end

    test "bank: prefers explicit Counterparty over Description when both present" do
      result = AutoDetectMapping.new(
        headers: [ "Transaction ID", "Date", "Amount", "Counterparty", "Description" ],
        kind: "bank"
      ).call

      assert_equal "Counterparty", result.mapping["counterparty"]
      refute_includes result.low_confidence, "counterparty"
      # description is not auto-mapped — leave it to the user to assign in the
      # dialog if they want it preserved. Counterparty is the more useful
      # destination for bank narratives in 90% of exports.
      assert_includes result.unmapped_headers, "Description"
    end

    test "accounting: detects canonical invoice headers" do
      result = AutoDetectMapping.new(
        headers: [ "Invoice Number", "Issue Date", "Due Date", "Amount", "Currency", "Status", "Payer" ],
        kind: "accounting"
      ).call

      assert_equal "Invoice Number", result.mapping["invoice_number"]
      assert_equal "Issue Date",     result.mapping["issue_date"]
      assert_equal "Due Date",       result.mapping["due_date"]
      assert_equal "Amount",         result.mapping["amount"]
      assert_equal "Currency",       result.mapping["currency"]
      assert_equal "Status",         result.mapping["status"]
      assert_equal "Payer",          result.mapping["payer"]
      refute_includes result.low_confidence, "payer"
    end

    test "accounting: payer falls back to Account Name with low confidence when no explicit payer header" do
      result = AutoDetectMapping.new(
        headers: [ "Invoice Number", "Issue Date", "Amount", "Account Name" ],
        kind: "accounting"
      ).call

      assert_equal "Account Name", result.mapping["payer"]
      assert_includes result.low_confidence, "payer"
    end

    test "accounting: due date does not steal the issue date slot" do
      result = AutoDetectMapping.new(
        headers: [ "Invoice Number", "Due Date", "Amount" ],
        kind: "accounting"
      ).call

      assert_equal "Due Date", result.mapping["due_date"]
      assert_nil result.mapping["issue_date"]
    end

    test "leaves unrelated columns in unmapped_headers" do
      result = AutoDetectMapping.new(
        headers: [ "Transaction ID", "Date", "Amount", "Currency", "Bank Branch", "Account Holder" ],
        kind: "bank"
      ).call

      assert_includes result.unmapped_headers, "Bank Branch"
      assert_includes result.unmapped_headers, "Account Holder"
    end

    test "is case-insensitive and tolerant of surrounding whitespace" do
      result = AutoDetectMapping.new(
        headers: [ "  TRANSACTION ID  ", "date", "AMOUNT" ],
        kind: "bank"
      ).call

      assert_equal "TRANSACTION ID", result.mapping["external_id"]
      assert_equal "date",           result.mapping["posted_date"]
      assert_equal "AMOUNT",         result.mapping["amount"]
    end

    test "raises on unsupported kind" do
      assert_raises(ArgumentError) do
        AutoDetectMapping.new(headers: [ "x" ], kind: "stripe").call
      end
    end

    test "empty headers list returns empty mapping without raising" do
      result = AutoDetectMapping.new(headers: [], kind: "bank").call
      assert_empty result.mapping
      assert_empty result.unmapped_headers
    end
  end
end
