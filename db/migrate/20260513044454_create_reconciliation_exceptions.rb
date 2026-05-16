class CreateReconciliationExceptions < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_exceptions do |t|
      t.references :reconciliation_run, null: false, foreign_key: true
      t.references :reconcilable_item, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :resolved_by_user, null: true, foreign_key: { to_table: :users }
      t.string :category, null: false
      t.text :llm_explanation
      t.datetime :resolved_at
      t.string :resolution

      t.timestamps
    end
    add_index :reconciliation_exceptions, [ :reconciliation_run_id, :reconcilable_item_id ],
              unique: true,
              name: "idx_unique_reconciliation_exception_per_run_item"
  end
end
