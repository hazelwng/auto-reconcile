class AuditEvent < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :workspace
  belongs_to :user, optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "AuditEvents are immutable" }
  before_update  { raise ActiveRecord::ReadOnlyRecord, "AuditEvents are immutable" }
end
