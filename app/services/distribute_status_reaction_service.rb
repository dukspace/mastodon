# frozen_string_literal: true

class DistributeStatusReactionService < BaseService
  def call(reaction, payload)
    return unless reaction.account.local?

    @reaction = reaction
    @status = reaction.status
    @payload = payload

    if @status.distributable?
      distribute_to_reactor_followers
    else
      distribute_to_status_audience
    end
  end

  private

  def distribute_to_reactor_followers
    target_inbox = status_author_inbox

    deliver_to_inboxes([target_inbox])
    ActivityPub::RawDistributionWorker.perform_async(@payload, @reaction.account_id, [target_inbox].compact)
  end

  def distribute_to_status_audience
    inboxes = mentioned_account_inboxes
    inboxes << status_author_inbox
    inboxes.concat(status_audience_follower_inboxes) if @status.private_visibility? && @status.account.local?

    deliver_to_inboxes(inboxes)
  end

  def mentioned_account_inboxes
    @status.active_mentions.includes(:account).filter_map do |mention|
      mention.account.preferred_inbox_url if mention.account.remote? && mention.account.activitypub?
    end
  end

  def status_author_inbox
    @status.account.preferred_inbox_url if @status.account.remote? && @status.account.activitypub?
  end

  def status_audience_follower_inboxes
    follower_ids = @status.account.passive_relationships.where(created_at: ..@status.created_at).select(:account_id)
    Account.where(id: follower_ids).inboxes
  end

  def deliver_to_inboxes(inboxes)
    inboxes = inboxes.compact.uniq
    return if inboxes.empty?

    # Only enqueue worker classes that also exist in Vanilla Mastodon so queued
    # deliveries remain executable after a code rollback.
    ActivityPub::DeliveryWorker.push_bulk(inboxes, limit: 1_000) do |inbox_url|
      [@payload, @reaction.account_id, inbox_url]
    end
  end
end
