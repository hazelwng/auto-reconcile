class CreateBankTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_transactions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.date :posted_date, null: false
      t.date :value_date
      t.bigint :balance_after_cents
      t.string :balance_after_currency
      t.string :txn_type, null: false
      t.string :counterparty
      t.text :memo
      t.string :check_number
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :discarded_at

      t.timestamps
    end
    add_index :bank_transactions, :discarded_at
  end
end
