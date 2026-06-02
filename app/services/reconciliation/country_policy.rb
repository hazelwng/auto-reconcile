module Reconciliation
  class CountryPolicy
    POLICIES = {
      "AU" => CountryPolicies::AustraliaPolicy,
      "JP" => CountryPolicies::JapanPolicy
    }.freeze

    def self.for(country_code)
      POLICIES.fetch(country_code.to_s.upcase, CountryPolicies::DefaultPolicy).new
    end
  end
end
