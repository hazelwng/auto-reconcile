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
  end
end
