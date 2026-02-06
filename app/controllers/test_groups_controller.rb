class TestGroupsController < ApplicationController
  before_action :set_test_group, only: [ :show, :update, :destroy, :toggle_active ]

  # GET /test_groups
  def index
    @test_groups = TestGroup.includes(:tests).active.ordered

    render json: {
      test_groups: @test_groups.map { |group| group_json(group) }
    }
  end

  # GET /test_groups/:id
  def show
    render json: {
      test_group: group_json(@test_group, detailed: true)
    }
  end

  # POST /test_groups
  def create
    @test_group = TestGroup.new(test_group_params)

    if @test_group.save
      render json: { test_group: group_json(@test_group, detailed: true) }, status: :created
    else
      render json: { errors: @test_group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /test_groups/:id
  def update
    if @test_group.update(test_group_params)
      render json: { test_group: group_json(@test_group, detailed: true) }
    else
      render json: { errors: @test_group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /test_groups/:id
  def destroy
    if @test_group.tests.any?
      render json: { error: "Cannot delete group with tests. Move or delete tests first." }, status: :unprocessable_entity
    else
      @test_group.destroy
      head :no_content
    end
  end

  # POST /test_groups/:id/toggle_active
  def toggle_active
    @test_group.update(active: !@test_group.active)
    render json: { test_group: group_json(@test_group) }
  end

  private

  def set_test_group
    @test_group = TestGroup.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Test group not found" }, status: :not_found
  end

  def test_group_params
    params.require(:test_group).permit(
      :name,
      :description,
      :color,
      :active
    )
  end

  def group_json(group, detailed: false)
    base = {
      id: group.id,
      name: group.name,
      description: group.description,
      color: group.color,
      active: group.active,
      tests_count: group.tests_count,
      created_at: group.created_at,
      updated_at: group.updated_at
    }

    if detailed
      base[:tests] = group.tests.ordered.map { |test|
        {
          id: test.id,
          name: test.name,
          test_key: test.test_key,
          active: test.active
        }
      }
    end

    base
  end
end
