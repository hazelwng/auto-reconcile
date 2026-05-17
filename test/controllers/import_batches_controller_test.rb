require "test_helper"

class ImportBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @data_source = data_sources(:demo_bank)
  end

  test "GET /import_batches/new renders the form with the data source select" do
    get new_import_batch_path
    assert_response :success
    assert_match "Import a CSV", response.body
    assert_match @data_source.name, response.body
  end

  test "POST /import_batches with file + data source creates batch and enqueues ImportBatchJob" do
    csv_io = StringIO.new("external_id,posted_date,amount,txn_type\nb-1,2026-04-01,10.00,credit\n")
    file = Rack::Test::UploadedFile.new(csv_io, "text/csv", original_filename: "import.csv")

    assert_difference -> { ImportBatch.count } => 1,
                      -> { enqueued_jobs.size } => 1 do
      post import_batches_path, params: {
        import_batch: { data_source_id: @data_source.id, source_file: file }
      }
    end

    batch = ImportBatch.last
    assert_redirected_to import_batch_path(batch)
    assert_equal "queued", batch.status
    assert batch.source_file.attached?
    assert_equal "ImportBatchJob", enqueued_jobs.last["job_class"]
    assert_equal [ batch.id ], enqueued_jobs.last["arguments"]
  end

  test "POST without a data_source_id re-renders new with an error" do
    csv_io = StringIO.new("external_id\nb-1\n")
    file = Rack::Test::UploadedFile.new(csv_io, "text/csv", original_filename: "x.csv")

    assert_no_difference [ "ImportBatch.count", "enqueued_jobs.size" ] do
      post import_batches_path, params: {
        import_batch: { data_source_id: "", source_file: file }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be selected/, response.body)
  end

  test "POST without a file re-renders new with an error" do
    assert_no_difference [ "ImportBatch.count", "enqueued_jobs.size" ] do
      post import_batches_path, params: {
        import_batch: { data_source_id: @data_source.id }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be uploaded/, response.body)
  end

  test "GET /import_batches/:id shows status and counters" do
    batch = ImportBatch.create!(
      data_source: @data_source,
      user: users(:hazel),
      status: "complete",
      row_count: 5, processed_count: 5, success_count: 3,
      error_count: 1, duplicate_count: 1,
      error_log: [ { "row_number" => 4, "external_id" => "bad-row", "error" => "StandardError: nope", "raw_row" => {} } ]
    )

    get import_batch_path(batch)
    assert_response :success
    assert_match "complete", response.body
    assert_match "bad-row", response.body
    assert_match "StandardError: nope", response.body
  end

  test "GET show for a batch in another workspace 404s" do
    other_ws = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}", base_currency: "AUD")
    other_ds = DataSource.create!(workspace: other_ws, name: "Other Bank", kind: "bank", currency: "AUD")
    other_batch = ImportBatch.create!(
      data_source: other_ds, user: users(:hazel), status: "queued",
      row_count: 0, processed_count: 0, success_count: 0,
      error_count: 0, duplicate_count: 0, error_log: []
    )

    get import_batch_path(other_batch)
    assert_response :not_found
  end
end
