class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :invoice_number, null: false
      t.date :issue_date, null: false
      t.date :due_date
      t.bigint :total_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "open"
      t.string :payer
      t.text :notes
      t.datetime :discarded_at

      t.timestamps
    end
    add_index :invoices, [ :workspace_id, :invoice_number ], unique: true
    add_index :invoices, :discarded_at
  end
end
