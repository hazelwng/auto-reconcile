class CreateReconciliationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_runs do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :triggered_by_user, null: false, foreign_key: { to_table: :users }
      t.bigint :source_a_id, null: false
      t.bigint :source_b_id, null: false
      t.date :date_range_start, null: false
      t.date :date_range_end, null: false
      t.string :status, null: false, default: "queued"
      t.jsonb :stats, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end
    add_foreign_key :reconciliation_runs, :data_sources, column: :source_a_id
    add_foreign_key :reconciliation_runs, :data_sources, column: :source_b_id
    add_index :reconciliation_runs, :source_a_id
    add_index :reconciliation_runs, :source_b_id
  end
end
