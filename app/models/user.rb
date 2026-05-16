class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :import_batches, dependent: :restrict_with_exception
  has_many :triggered_reconciliation_runs,
           class_name: "ReconciliationRun",
           foreign_key: :triggered_by_user_id,
           dependent: :restrict_with_exception,
           inverse_of: :triggered_by_user
  has_many :confirmed_matches,
           class_name: "Match",
           foreign_key: :confirmed_by_user_id,
           dependent: :nullify,
           inverse_of: :confirmed_by_user
  has_many :resolved_reconciliation_exceptions,
           class_name: "ReconciliationException",
           foreign_key: :resolved_by_user_id,
           dependent: :nullify,
           inverse_of: :resolved_by_user
  has_many :audit_events, dependent: :nullify

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
end
