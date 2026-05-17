require "test_helper"

class DataSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ds = data_sources(:demo_bank)
  end

  test "GET /data_sources renders the list" do
    get data_sources_path
    assert_response :success
    assert_match "Demo Bank", response.body
  end

  test "GET /data_sources/:id/edit pre-fills the JSON textarea from the stored mapping" do
    @ds.update!(schema_mapping: { "external_id" => "Reference" })

    get edit_data_source_path(@ds)
    assert_response :success
    # JSON.pretty_generate includes pretty whitespace; assert key text appears.
    assert_match(/"external_id"/, response.body)
    assert_match(/"Reference"/, response.body)
  end

  test "PATCH with valid JSON persists schema_mapping" do
    json = '{ "external_id": "Ref", "amount": "Net" }'

    patch data_source_path(@ds), params: {
      data_source: {
        name: @ds.name,
        kind: @ds.kind,
        currency: @ds.currency,
        schema_mapping_json: json
      }
    }

    assert_redirected_to data_sources_path
    assert_equal({ "external_id" => "Ref", "amount" => "Net" }, @ds.reload.schema_mapping)
  end

  test "PATCH with malformed JSON re-renders edit with an alert and does NOT mutate the record" do
    @ds.update!(schema_mapping: { "external_id" => "old" })

    patch data_source_path(@ds), params: {
      data_source: {
        name: @ds.name,
        kind: @ds.kind,
        currency: @ds.currency,
        schema_mapping_json: "{ not valid json"
      }
    }

    assert_response :unprocessable_entity
    assert_match(/not valid JSON/, response.body)
    # Mapping is unchanged.
    assert_equal({ "external_id" => "old" }, @ds.reload.schema_mapping)
  end

  test "PATCH with valid JSON that is not an object is rejected" do
    patch data_source_path(@ds), params: {
      data_source: {
        name: @ds.name,
        kind: @ds.kind,
        currency: @ds.currency,
        schema_mapping_json: '["just", "an", "array"]'
      }
    }

    assert_response :unprocessable_entity
    assert_match(/must be a JSON object/, response.body)
  end

  test "PATCH with empty schema_mapping_json clears the mapping" do
    @ds.update!(schema_mapping: { "external_id" => "old" })

    patch data_source_path(@ds), params: {
      data_source: {
        name: @ds.name,
        kind: @ds.kind,
        currency: @ds.currency,
        schema_mapping_json: ""
      }
    }

    assert_redirected_to data_sources_path
    assert_equal({}, @ds.reload.schema_mapping)
  end
end
