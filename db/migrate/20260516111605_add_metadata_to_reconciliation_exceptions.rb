class AddMetadataToReconciliationExceptions < ActiveRecord::Migration[8.1]
  def change
    add_column :reconciliation_exceptions, :metadata, :jsonb, default: {}, null: false
  end
end
