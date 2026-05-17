class DataSourcesController < ApplicationController
  before_action :load_data_source, only: [ :edit, :update ]

  def index
    @data_sources = current_workspace.data_sources.order(:kind, :name)
  end

  def edit
    # The form binds to a string field `schema_mapping_json` so the user
    # can paste raw JSON. We pre-fill it from the stored jsonb.
    @schema_mapping_json = JSON.pretty_generate(@data_source.schema_mapping)
  end

  def update
    parsed_mapping, parse_error = parse_schema_mapping(params.dig(:data_source, :schema_mapping_json))

    if parse_error
      @schema_mapping_json = params.dig(:data_source, :schema_mapping_json)
      flash.now[:alert] = "schema_mapping is not valid JSON: #{parse_error}"
      render :edit, status: :unprocessable_entity and return
    end

    if @data_source.update(allowed_params.merge(schema_mapping: parsed_mapping))
      redirect_to data_sources_path, notice: "Data source updated."
    else
      @schema_mapping_json = params.dig(:data_source, :schema_mapping_json)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_data_source
    @data_source = current_workspace.data_sources.find(params[:id])
  end

  def allowed_params
    params.require(:data_source).permit(:name, :kind, :currency)
  end

  # Returns [parsed_hash_or_nil, error_message_or_nil].
  # An empty/blank textarea is treated as `{}` (clears the mapping).
  # JSON that parses to anything other than a Hash is rejected.
  def parse_schema_mapping(raw)
    return [ {}, nil ] if raw.blank?

    parsed = JSON.parse(raw)
    return [ nil, "must be a JSON object, got #{parsed.class.name}" ] unless parsed.is_a?(Hash)

    [ parsed, nil ]
  rescue JSON::ParserError => e
    [ nil, e.message ]
  end
end
