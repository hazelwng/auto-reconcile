require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "normalizes country code" do
    workspace = Workspace.create!(name: "Japan Co", slug: "japan-co", base_currency: "JPY", country_code: "jp")

    assert_equal "JP", workspace.country_code
  end

  test "rejects unsupported country code" do
    workspace = Workspace.new(name: "Other Co", slug: "other-co", base_currency: "USD", country_code: "US")

    assert_not workspace.valid?
    assert_includes workspace.errors[:country_code], "is not included in the list"
  end
end
