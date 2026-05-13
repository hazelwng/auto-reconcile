class Membership < ApplicationRecord
  ROLES = %w[owner admin member viewer].freeze

  belongs_to :workspace
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :workspace_id }
end
