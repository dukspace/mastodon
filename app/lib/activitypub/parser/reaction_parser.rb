# frozen_string_literal: true

class ActivityPub::Parser::ReactionParser
  include JsonLdHelper

  ParsedReaction = Data.define(:name, :custom_emoji)

  def initialize(json, account)
    @json = json
    @account = account
  end

  def parse
    value = reaction_value
    return if value.blank? || !value.is_a?(String)

    if custom_shortcode?(value)
      shortcode = value[1...-1]
      emoji = find_or_create_custom_emoji(shortcode)
      return if emoji.nil?

      ParsedReaction.new(name: shortcode, custom_emoji: emoji)
    elsif ReactionValidator::SUPPORTED_EMOJIS.include?(value)
      ParsedReaction.new(name: value, custom_emoji: nil)
    end
  end

  private

  def reaction_value
    @json['_misskey_reaction'].presence || @json['content'].presence
  end

  def custom_shortcode?(value)
    value.start_with?(':') && value.end_with?(':') && value.length > 2 && CustomEmoji::SHORTCODE_ONLY_RE.match?(value[1...-1])
  end

  def find_or_create_custom_emoji(shortcode)
    emoji = CustomEmoji.find_by(shortcode: shortcode, domain: @account.domain)
    raw_emoji = as_array(@json['tag']).find do |tag|
      next false unless tag.is_a?(Hash) && equals_or_includes?(tag['type'], 'Emoji')

      ActivityPub::Parser::CustomEmojiParser.new(tag).shortcode == shortcode
    end

    return emoji if raw_emoji.nil?

    parser = ActivityPub::Parser::CustomEmojiParser.new(raw_emoji)
    return emoji if parser.image_remote_url.blank?

    emoji ||= CustomEmoji.new(domain: @account.domain, shortcode: shortcode, uri: parser.uri)
    return emoji if emoji.persisted? && emoji.image_remote_url == parser.image_remote_url

    emoji.image_remote_url = parser.image_remote_url
    emoji.save
    emoji if emoji.persisted?
  rescue Seahorse::Client::NetworkingError => e
    Rails.logger.warn "Error storing reaction emoji: #{e}"
    emoji
  end
end
