class CreateDataSources < ActiveRecord::Migration[8.1]
  def change
    create_table :data_sources do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :currency, null: false, default: "USD"
      t.jsonb :schema_mapping, null: false, default: {}
      t.datetime :last_synced_at
      t.datetime :discarded_at

      t.timestamps
    end
    add_index :data_sources, :discarded_at
  end
end
