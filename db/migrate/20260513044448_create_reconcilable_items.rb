class CreateReconcilableItems < ActiveRecord::Migration[8.1]
  def change
    create_table :reconcilable_items do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :data_source, null: false, foreign_key: true
      t.references :import_batch, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.string :amount_currency, null: false, default: "USD"
      t.date :occurred_on, null: false
      t.text :description, null: false, default: ""
      t.string :external_id
      t.string :external_id_hash, null: false
      t.string :status, null: false, default: "unmatched"
      t.references :item, polymorphic: true, null: false
      t.datetime :discarded_at

      t.timestamps
    end
    add_index :reconcilable_items, [ :workspace_id, :occurred_on ]
    add_index :reconcilable_items, [ :workspace_id, :amount_cents ]
    add_index :reconcilable_items, [ :data_source_id, :external_id_hash ], unique: true
    add_index :reconcilable_items, :discarded_at
  end
end
