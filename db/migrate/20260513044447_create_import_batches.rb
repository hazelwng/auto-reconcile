class CreateImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :import_batches do |t|
      t.references :data_source, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.integer :row_count, null: false, default: 0
      t.integer :processed_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.jsonb :error_log, null: false, default: []
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
