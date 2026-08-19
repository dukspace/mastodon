# frozen_string_literal: true

class ActivityPub::Activity::Like < ActivityPub::Activity
  def perform
    original_status = status_from_uri(object_uri)

    return if original_status.nil? || !original_status.account.local? || delete_arrived_first?(@json['id'])

    parsed_reaction = ActivityPub::Parser::ReactionParser.new(@json, @account).parse
    favourite = original_status.favourites.find_or_create_by!(account: @account)
    status_reaction = if parsed_reaction
                        CreateStatusReactionService.new.call(
                          @account,
                          original_status,
                          name: parsed_reaction.name,
                          domain: parsed_reaction.custom_emoji&.domain,
                          activity_type: :like,
                          activity_uri: @json['id'],
                          favourite: favourite,
                          authorize: false,
                          federate: false,
                          notify: false
                        )
                      end

    LocalNotificationWorker.perform_async(original_status.account_id, favourite.id, 'Favourite', 'favourite', { 'status_reaction_id' => status_reaction&.id }.compact)
    Trends.statuses.register(original_status) if parsed_reaction.nil?
  end
end
