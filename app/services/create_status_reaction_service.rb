# frozen_string_literal: true

class CreateStatusReactionService < BaseService
  include Authorization
  include Payloadable

  def call(account, status, name:, domain: nil, activity_type: nil, activity_uri: nil, favourite: nil, authorize: true, federate: true, notify: true, with_rate_limit: false)
    status = status.reblog if status.reblog?
    authorize_with account, status, :favourite? if authorize

    normalized_name, custom_emoji = resolve_reaction(name, domain)
    raise ActiveRecord::RecordNotFound if normalized_name.nil?

    selected_type = activity_type&.to_sym || delivery_type_for(status)
    existing = nil

    reaction = StatusReaction.transaction do
      status.lock!
      existing = StatusReaction.find_by(account: account, status: status)
      if duplicate_reaction?(existing, normalized_name, custom_emoji, activity_uri)
        existing
      else
        linked_favourite = existing&.favourite if existing&.favourite_id.present? && favourite.nil?
        existing&.destroy!
        linked_favourite&.destroy!

        StatusReaction.create!(
          account: account,
          status: status,
          name: normalized_name,
          custom_emoji: custom_emoji,
          activity_type: selected_type,
          activity_uri: activity_uri,
          favourite: favourite,
          rate_limit: with_rate_limit
        )
      end
    end

    return reaction if reaction.equal?(existing)

    ReactionDomainCapability.observe!(account.domain, selected_type) if activity_uri.present?
    federate_reaction_change(existing, reaction) if federate && account.local?
    notify_local_author(reaction) if notify && status.account.local? && status.account_id != account.id && favourite.nil?
    reaction
  end

  private

  def duplicate_reaction?(existing, name, custom_emoji, activity_uri)
    return false if existing.nil?
    return existing.activity_uri == activity_uri if activity_uri.present?

    existing.activity_uri.nil? && existing.name == name && existing.custom_emoji_id == custom_emoji&.id
  end

  def resolve_reaction(value, domain)
    value = value.to_s
    value = value[1...-1] if value.start_with?(':') && value.end_with?(':')

    return [value, nil] if ReactionValidator::SUPPORTED_EMOJIS.include?(value)
    return if !CustomEmoji::SHORTCODE_ONLY_RE.match?(value) || value.length > CustomEmoji::MAX_SHORTCODE_SIZE

    emoji_scope = CustomEmoji.where(shortcode: value, domain: domain.presence)
    emoji_scope = emoji_scope.enabled if domain.blank?
    emoji = emoji_scope.first
    emoji ? [value, emoji] : nil
  end

  def delivery_type_for(_status)
    # Public reactions fan out to heterogeneous follower domains, so use the
    # broadly-supported Like representation for every new local activity.
    :like
  end

  def federate_reaction_change(existing, reaction)
    distribute(existing, ActivityPub::UndoStatusReactionSerializer) if existing

    if reaction.status.account.remote? && reaction.activity_type_like?
      favourite = Favourite.find_by(account: reaction.account, status: reaction.status)
      deliver_to_author(favourite, ActivityPub::UndoLikeSerializer) if favourite
    end

    distribute(reaction, ActivityPub::StatusReactionSerializer)
  end

  def distribute(object, serializer)
    DistributeStatusReactionService.new.call(object, serialize_payload(object, serializer).to_json)
  end

  def deliver_to_author(object, serializer)
    inbox_url = object.status.account.inbox_url
    ActivityPub::DeliveryWorker.perform_async(serialize_payload(object, serializer).to_json, object.account_id, inbox_url)
  end

  def notify_local_author(reaction)
    NotifyService.new.call(reaction.status.account, :emoji_reaction, reaction.account, status_reaction: reaction)
  end
end
