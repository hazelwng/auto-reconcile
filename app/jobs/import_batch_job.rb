class ImportBatchJob < ApplicationJob
  queue_as :default

  def perform(import_batch_id)
    batch = ImportBatch.find(import_batch_id)
    importer_for(batch).new(batch).call
  end

  private

  # Empty jsonb (`{}`) is `blank?` in Rails, so `.present?` correctly
  # selects MappedCsv only when the user has configured a non-empty mapping.
  def importer_for(batch)
    if batch.data_source.schema_mapping.present?
      Importers::MappedCsv
    else
      Importers::FixedCsv
    end
  end
end
