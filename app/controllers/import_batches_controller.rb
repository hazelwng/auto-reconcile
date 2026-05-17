class ImportBatchesController < ApplicationController
  def new
    @import_batch = ImportBatch.new(data_source_id: params[:data_source_id])
    @data_sources = current_workspace.data_sources.order(:kind, :name)
  end

  def create
    @data_sources = current_workspace.data_sources.order(:kind, :name)
    data_source = current_workspace.data_sources.find_by(id: params.dig(:import_batch, :data_source_id))
    file = params.dig(:import_batch, :source_file)

    @import_batch = ImportBatch.new(
      data_source: data_source,
      user: current_user,
      status: "queued",
      row_count: 0, processed_count: 0, success_count: 0,
      error_count: 0, duplicate_count: 0,
      error_log: []
    )

    if data_source.nil?
      @import_batch.errors.add(:data_source_id, "must be selected")
      render :new, status: :unprocessable_entity and return
    end
    if file.blank?
      @import_batch.errors.add(:source_file, "must be uploaded")
      render :new, status: :unprocessable_entity and return
    end

    @import_batch.source_file.attach(file)

    if @import_batch.save
      ImportBatchJob.perform_later(@import_batch.id)
      redirect_to import_batch_path(@import_batch), notice: "Import queued."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @import_batch = ImportBatch.find(params[:id])
    # Defence-in-depth: prevent showing a batch from a different workspace.
    raise ActiveRecord::RecordNotFound if @import_batch.data_source.workspace_id != current_workspace.id
  end
end
