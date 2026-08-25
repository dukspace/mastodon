# frozen_string_literal: true

class ActivityPub::StatusReactionAudience
  def initialize(reaction)
    @reaction = reaction
    @status = reaction.status
    @tag_manager = ActivityPub::TagManager.instance
  end

  def to
    case @status.visibility
    when 'public'
      [ActivityPub::TagManager::COLLECTIONS[:public]]
    when 'unlisted'
      [reactor_followers_uri, status_author_uri].compact.uniq
    when 'private'
      (restricted_audience + [status_followers_uri]).compact.uniq
    else
      restricted_audience
    end
  end

  def cc
    case @status.visibility
    when 'public'
      [reactor_followers_uri, status_author_uri].compact.uniq
    when 'unlisted'
      [ActivityPub::TagManager::COLLECTIONS[:public]]
    else
      []
    end
  end

  private

  def reactor_followers_uri
    @tag_manager.followers_uri_for(@reaction.account)
  end

  def status_author_uri
    @tag_manager.uri_for(@status.account)
  end

  def status_followers_uri
    @tag_manager.followers_uri_for(@status.account) if @status.account.local?
  end

  def restricted_audience
    ([status_author_uri] + @status.active_mentions.includes(:account).flat_map { |mention| account_uris(mention.account) }).uniq
  end

  def account_uris(account)
    [@tag_manager.uri_for(account), (@tag_manager.followers_uri_for(account) if account.group?)].compact
  end
end
