class TestsController < ApplicationController
  before_action :set_test, only: [ :show, :update, :destroy, :toggle_active ]

  # GET /tests
  def index
    @tests = Test.includes(:test_group).active.ordered

    # Filter by group if provided
    @tests = @tests.by_group(params[:group_id]) if params[:group_id].present?

    render json: {
      tests: @tests.map { |test| test_json(test) }
    }
  end

  # GET /tests/:id
  def show
    render json: { test: test_json(@test, detailed: true) }
  end

  # POST /tests
  def create
    test_group = TestGroup.find(params[:test][:test_group_id])
    @test = test_group.tests.new(test_params)

    if @test.save
      render json: { test: test_json(@test, detailed: true) }, status: :created
    else
      render json: { errors: @test.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Test group not found" }, status: :not_found
  end

  # PATCH/PUT /tests/:id
  def update
    if @test.update(test_params)
      render json: { test: test_json(@test, detailed: true) }
    else
      render json: { errors: @test.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /tests/:id
  def destroy
    @test.destroy
    head :no_content
  end

  # POST /tests/:id/toggle_active
  def toggle_active
    @test.update(active: !@test.active)
    render json: { test: test_json(@test) }
  end

  # POST /tests/import
  def import
    uploaded_file = params[:file]

    unless uploaded_file
      return render json: { error: "No file provided" }, status: :unprocessable_entity
    end

    begin
      json_data = JSON.parse(uploaded_file.read)

      imported_count = 0
      errors = []

      json_data.each do |test_data|
        group_name = test_data["test_group"] || test_data["group"]
        group = TestGroup.find_or_create_by!(name: group_name)

        begin
          Test.import_from_json(test_data, group)
          imported_count += 1
        rescue => e
          errors << "Failed to import #{test_data['test_key']}: #{e.message}"
        end
      end

      render json: {
        imported: imported_count,
        errors: errors
      }
    rescue JSON::ParserError => e
      render json: { error: "Invalid JSON file: #{e.message}" }, status: :unprocessable_entity
    rescue => e
      render json: { error: "Import failed: #{e.message}" }, status: :unprocessable_entity
    end
  end

  # GET /tests/export
  def export
    tests = Test.active.includes(:test_group)

    # Filter by group if provided
    tests = tests.by_group(params[:group_id]) if params[:group_id].present?

    export_data = tests.map(&:export_json)

    send_data export_data.to_json,
              filename: "tests_export_#{Time.now.to_i}.json",
              type: "application/json",
              disposition: "attachment"
  end

  private

  def set_test
    @test = Test.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Test not found" }, status: :not_found
  end

  def set_test_group
    @test_group = TestGroup.find(params[:test_group_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Test group not found" }, status: :not_found
  end

  def test_params
    params.require(:test).permit(
      :name,
      :description,
      :test_key,
      :test_details,
      :active,
      :test_group_id,
      data_sources: []
    )
  end

  def test_json(test, detailed: false)
    base = {
      id: test.id,
      name: test.name,
      description: test.description,
      test_key: test.test_key,
      test_group: {
        id: test.test_group.id,
        name: test.test_group.name
      },
      active: test.active,
      data_sources: test.data_sources,
      created_at: test.created_at,
      updated_at: test.updated_at
    }

    if detailed
      base.merge!(
        test_details: test.test_details
      )
    end

    base
  end
end
