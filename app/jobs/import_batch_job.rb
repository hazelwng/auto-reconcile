class ImportBatchJob < ApplicationJob
  queue_as :default

  def perform(import_batch_id)
    batch = ImportBatch.find(import_batch_id)
    importer_for(batch).new(batch).call
  end

  private

  def importer_for(_batch)
    Importers::FixedCsv
  end
end
