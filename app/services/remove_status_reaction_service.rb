# frozen_string_literal: true

class RemoveStatusReactionService < BaseService
  include Payloadable

  def call(account, status, reaction: nil, federate: true, restore_favourite: true)
    status = status.reblog if status.reblog?
    reaction ||= StatusReaction.find_by!(account: account, status: status)

    if federate && status.account.remote? && account.local?
      inbox_url = status.account.inbox_url
      ActivityPub::DeliveryWorker.perform_async(
        serialize_payload(reaction, ActivityPub::UndoStatusReactionSerializer).to_json,
        account.id,
        inbox_url
      )

      if restore_favourite && reaction.activity_type_like?
        favourite = Favourite.find_by(account: account, status: status)
        if favourite
          ActivityPub::DeliveryWorker.perform_async(
            serialize_payload(favourite, ActivityPub::LikeSerializer).to_json,
            account.id,
            inbox_url
          )
        end
      end
    end

    reaction.destroy!
    reaction
  end
end
