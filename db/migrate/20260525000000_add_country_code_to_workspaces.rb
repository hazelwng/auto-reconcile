class AddCountryCodeToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :country_code, :string, null: false, default: "DEFAULT"
  end
end
