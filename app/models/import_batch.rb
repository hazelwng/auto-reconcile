class ImportBatch < ApplicationRecord
  STATUSES = %w[queued processing complete failed].freeze

  belongs_to :data_source
  belongs_to :user
  has_many :reconcilable_items, dependent: :destroy

  has_one_attached :source_file

  validates :status, presence: true, inclusion: { in: STATUSES }
end
