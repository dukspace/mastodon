# frozen_string_literal: true

class ActivityPub::Activity::Like < ActivityPub::Activity
  def perform
    original_status = status_from_uri(object_uri)

    return if original_status.nil? || !reaction_allowed_for_status?(original_status) || delete_arrived_first?(@json['id'])

    parsed_reaction = ActivityPub::Parser::ReactionParser.new(@json, @account).parse
    return store_remote_status_reaction(original_status, parsed_reaction) unless original_status.account.local?

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

  private

  def store_remote_status_reaction(status, parsed_reaction)
    return if parsed_reaction.nil?

    CreateStatusReactionService.new.call(
      @account,
      status,
      name: parsed_reaction.name,
      domain: parsed_reaction.custom_emoji&.domain,
      activity_type: :like,
      activity_uri: @json['id'],
      authorize: false,
      federate: false,
      notify: false
    )
  end
end
