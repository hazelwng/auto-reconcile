class CreateMatchLegs < ActiveRecord::Migration[8.1]
  def change
    create_table :match_legs do |t|
      t.references :match, null: false, foreign_key: true
      t.references :reconcilable_item, null: false, foreign_key: true
      t.string :side, null: false
      t.bigint :allocated_amount_cents, null: false
      t.string :allocated_currency, null: false, default: "USD"

      t.timestamps
    end
    add_index :match_legs, [ :match_id, :reconcilable_item_id ], unique: true
  end
end
