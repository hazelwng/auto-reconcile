class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.references :reconciliation_run, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :confirmed_by_user, null: true, foreign_key: { to_table: :users }
      t.decimal :confidence, precision: 5, scale: 4, null: false, default: 0
      t.string :method, null: false
      t.string :status, null: false, default: "proposed"
      t.datetime :confirmed_at
      t.string :rejected_reason
      t.text :reasoning
      t.datetime :discarded_at

      t.timestamps
    end
    add_index :matches, :discarded_at
  end
end
