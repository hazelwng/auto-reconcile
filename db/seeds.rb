# Phase 1a seed: 1 user, 1 workspace, 1 membership, 2 data sources.
# Idempotent — safe to rerun.

user = User.find_or_create_by!(email: "hazel@example.com") do |u|
  u.name = "Hazel"
end

workspace = Workspace.find_or_create_by!(slug: "demo-co") do |w|
  w.name = "Demo Co"
  w.base_currency = "AUD"
  w.settings = {}
end

Membership.find_or_create_by!(workspace: workspace, user: user) do |m|
  m.role = "owner"
end

DataSource.find_or_create_by!(workspace: workspace, name: "Demo Bank") do |ds|
  ds.kind = "bank"
  ds.currency = "AUD"
  ds.schema_mapping = {}
end

DataSource.find_or_create_by!(workspace: workspace, name: "Demo Invoices") do |ds|
  ds.kind = "accounting"
  ds.currency = "AUD"
  ds.schema_mapping = {}
end

puts "Seeded: #{User.count} user, #{Workspace.count} workspace, " \
     "#{Membership.count} membership, #{DataSource.count} data sources"
