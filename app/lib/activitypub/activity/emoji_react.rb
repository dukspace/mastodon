# frozen_string_literal: true

class ActivityPub::Activity::EmojiReact < ActivityPub::Activity
  def perform
    original_status = status_from_uri(object_uri)
    return if original_status.nil? || delete_arrived_first?(@json['id'])

    parsed_reaction = ActivityPub::Parser::ReactionParser.new(@json, @account).parse
    return if parsed_reaction.nil?

    CreateStatusReactionService.new.call(
      @account,
      original_status,
      name: parsed_reaction.name,
      domain: parsed_reaction.custom_emoji&.domain,
      activity_type: :emoji_react,
      activity_uri: @json['id'],
      authorize: false,
      federate: false,
      notify: original_status.account.local?
    )
  end
end
