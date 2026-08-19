# frozen_string_literal: true

class CreateStatusReactionService < BaseService
  include Authorization
  include Payloadable

  def call(account, status, name:, domain: nil, activity_type: nil, activity_uri: nil, favourite: nil, authorize: true, federate: true, notify: true)
    status = status.reblog if status.reblog?
    authorize_with account, status, :favourite? if authorize

    normalized_name, custom_emoji = resolve_reaction(name, domain)
    raise ActiveRecord::RecordNotFound if normalized_name.nil?

    selected_type = activity_type&.to_sym || delivery_type_for(status)
    existing = nil

    reaction = StatusReaction.transaction do
      status.lock!
      existing = StatusReaction.find_by(account: account, status: status)
      if activity_uri.present? && existing&.activity_uri == activity_uri
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
          favourite: favourite
        )
      end
    end

    return reaction if reaction.equal?(existing)

    ReactionDomainCapability.observe!(account.domain, selected_type) if activity_uri.present?
    replace_remote_reaction(existing, reaction) if federate && status.account.remote?
    notify_local_author(reaction) if notify && status.account.local? && status.account_id != account.id && favourite.nil?
    reaction
  end

  private

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

  def delivery_type_for(status)
    return :local if status.account.local?

    ReactionDomainCapability.preferred_for(status.account.domain)
  end

  def replace_remote_reaction(existing, reaction)
    inbox_url = reaction.status.account.inbox_url

    deliver(existing, ActivityPub::UndoStatusReactionSerializer, inbox_url) if existing

    if reaction.activity_type_like?
      favourite = Favourite.find_by(account: reaction.account, status: reaction.status)
      deliver(favourite, ActivityPub::UndoLikeSerializer, inbox_url) if favourite
    end

    deliver(reaction, ActivityPub::StatusReactionSerializer, inbox_url)
  end

  def deliver(object, serializer, inbox_url)
    ActivityPub::DeliveryWorker.perform_async(serialize_payload(object, serializer).to_json, object.account_id, inbox_url)
  end

  def notify_local_author(reaction)
    NotifyService.new.call(reaction.status.account, :emoji_reaction, reaction.account, status_reaction: reaction)
  end
end
