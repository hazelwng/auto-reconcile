class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :base_currency, null: false, default: "USD"
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
    add_index :workspaces, :slug, unique: true
  end
end
