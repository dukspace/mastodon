# frozen_string_literal: true

class ActivityPub::UndoStatusReactionSerializer < ActivityPub::Serializer
  attributes :id, :type, :actor, :to, :cc

  has_one :object, serializer: ActivityPub::StatusReactionSerializer

  def id
    "#{object.local_activity_uri}/undo"
  end

  def type
    'Undo'
  end

  def actor
    ActivityPub::TagManager.instance.uri_for(object.account)
  end

  def to
    audience.to
  end

  def cc
    audience.cc
  end

  private

  def audience
    @audience ||= ActivityPub::StatusReactionAudience.new(object)
  end
end
