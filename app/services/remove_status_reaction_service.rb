# frozen_string_literal: true

class RemoveStatusReactionService < BaseService
  include Payloadable

  def call(account, status, reaction: nil, federate: true, restore_favourite: true)
    status = status.reblog if status.reblog?
    reaction ||= StatusReaction.find_by!(account: account, status: status)

    if federate && account.local?
      distribute(reaction, ActivityPub::UndoStatusReactionSerializer)

      if status.account.remote? && restore_favourite && reaction.activity_type_like?
        favourite = Favourite.find_by(account: account, status: status)
        deliver_to_author(favourite, ActivityPub::LikeSerializer) if favourite
      end
    end

    reaction.destroy!
    reaction
  end

  private

  def distribute(object, serializer)
    DistributeStatusReactionService.new.call(object, serialize_payload(object, serializer).to_json)
  end

  def deliver_to_author(object, serializer)
    inbox_url = object.status.account.inbox_url
    ActivityPub::DeliveryWorker.perform_async(serialize_payload(object, serializer).to_json, object.account_id, inbox_url)
  end
end
