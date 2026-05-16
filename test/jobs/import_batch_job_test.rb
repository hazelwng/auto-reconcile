require "test_helper"

class ImportBatchJobTest < ActiveJob::TestCase
  setup do
    @bank_batch = import_batches(:queued_bank)
  end

  test "importer_for returns FixedCsv when schema_mapping is empty" do
    @bank_batch.data_source.update!(schema_mapping: {})

    assert_equal Importers::FixedCsv, ImportBatchJob.new.send(:importer_for, @bank_batch)
  end

  test "importer_for returns MappedCsv when schema_mapping is non-empty" do
    @bank_batch.data_source.update!(schema_mapping: { "external_id" => "Ref" })

    assert_equal Importers::MappedCsv, ImportBatchJob.new.send(:importer_for, @bank_batch)
  end
end
