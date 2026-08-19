# frozen_string_literal: true

# == Schema Information
#
# Table name: reaction_domain_capabilities
#
#  domain                  :string           not null, primary key
#  last_observed_at        :datetime         not null
#  supports_emoji_react    :boolean          default(FALSE), not null
#  supports_like_reactions :boolean          default(FALSE), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
class ReactionDomainCapability < ApplicationRecord
  self.primary_key = :domain

  normalizes :domain, with: ->(domain) { domain.downcase.strip }

  validates :domain, presence: true

  class << self
    def observe!(domain, activity_type)
      return if domain.blank? || activity_type.to_sym == :local

      attribute = activity_type.to_sym == :emoji_react ? :supports_emoji_react : :supports_like_reactions
      normalized_domain = domain.downcase.strip
      capability = create_or_find_by!(domain: normalized_domain) do |record|
        record.last_observed_at = Time.current
      end
      capability.update!({ attribute => true }.merge(last_observed_at: Time.current))
    end

    def preferred_for(domain)
      find_by(domain: domain.to_s.downcase.strip)&.supports_emoji_react? ? :emoji_react : :like
    end
  end
end
