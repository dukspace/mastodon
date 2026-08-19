# frozen_string_literal: true

class Api::V1::Statuses::ReactionsController < Api::BaseController
  include Authorization

  before_action -> { doorkeeper_authorize! :write, :'write:favourites' }
  before_action :require_user!
  before_action :set_status

  override_rate_limit_headers :update, family: :reactions

  def update
    CreateStatusReactionService.new.call(
      current_account,
      @status,
      name: params[:id],
      domain: params[:domain],
      with_rate_limit: true
    )
    render_status
  end

  def destroy
    authorize @status, :favourite?
    reaction = StatusReaction.find_by!(account: current_account, status: @status.proper)
    raise ActiveRecord::RecordNotFound unless matches_requested_reaction?(reaction)

    RemoveStatusReactionService.new.call(current_account, @status, reaction: reaction)
    render_status
  end

  private

  def set_status
    @status = Status.find(params[:status_id])
  end

  def matches_requested_reaction?(reaction)
    requested_name = params[:id].to_s
    requested_name = requested_name[1...-1] if requested_name.start_with?(':') && requested_name.end_with?(':')
    reaction.name == requested_name && reaction.custom_emoji&.domain.to_s == params[:domain].to_s
  end

  def render_status
    relationships = StatusRelationshipsPresenter.new([@status], current_account.id)
    render json: @status, serializer: REST::StatusSerializer, relationships: relationships
  end
end
