class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :payload, null: false, default: {}
      t.string :ip_address
      t.string :user_agent

      t.datetime :created_at, null: false
    end
    add_index :audit_events, [ :target_type, :target_id ]
  end
end
