# frozen_string_literal: true

class ActivityPub::StatusReactionSerializer < ActivityPub::Serializer
  context_extensions :emoji, :misskey_reactions, :emoji_reactions

  attributes :id, :type, :actor, :content
  attribute :reaction, key: :_misskey_reaction, if: :like?
  attribute :target, key: :object

  has_many :tags, key: :tag, serializer: ActivityPub::EmojiSerializer, if: :custom?

  def id
    object.local_activity_uri
  end

  def type
    object.activity_type_emoji_react? ? 'EmojiReact' : 'Like'
  end

  def actor
    ActivityPub::TagManager.instance.uri_for(object.account)
  end

  def content
    object.display_name
  end

  alias reaction content

  def target
    ActivityPub::TagManager.instance.uri_for(object.status)
  end

  def tags
    [object.custom_emoji]
  end

  def custom?
    object.custom?
  end

  def like?
    object.activity_type_like?
  end
end
