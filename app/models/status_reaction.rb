# frozen_string_literal: true

# == Schema Information
#
# Table name: status_reactions
#
#  id              :bigint(8)        not null, primary key
#  activity_type   :integer          default("local"), not null
#  activity_uri    :string
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint(8)        not null
#  custom_emoji_id :bigint(8)
#  favourite_id    :bigint(8)
#  status_id       :bigint(8)        not null
#
class StatusReaction < ApplicationRecord
  include RateLimitable
  include Redisable

  rate_limit by: :account, family: :reactions

  belongs_to :status, inverse_of: :status_reactions
  belongs_to :account, inverse_of: :status_reactions
  belongs_to :custom_emoji, optional: true
  belongs_to :favourite, optional: true

  has_one :notification, inverse_of: :status_reaction, dependent: :destroy

  enum :activity_type, { local: 0, like: 1, emoji_react: 2 }, prefix: true

  validates :name, presence: true, length: { maximum: CustomEmoji::MAX_SHORTCODE_SIZE }
  validates :account_id, uniqueness: { scope: :status_id }
  validate :valid_reaction_name

  after_commit :schedule_status_update, on: %i(create destroy)

  def custom?
    custom_emoji_id.present?
  end

  def display_name
    ReactionValidator::SUPPORTED_EMOJIS.include?(name) ? name : ":#{name}:"
  end

  def local_activity_uri
    [ActivityPub::TagManager.instance.uri_for(account), '#reactions/', id].join
  end

  def federated_activity_uri
    activity_uri.presence || local_activity_uri
  end

  class << self
    def summaries_for(status_ids, account = nil)
      return {} if status_ids.empty?

      select_values = [:status_id, :name, :custom_emoji_id, 'COUNT(*) AS count']
      select_values << if account.nil?
                         'FALSE AS me'
                       else
                         sanitize_sql_array([<<~SQL.squish, account_id: account.id])
                           EXISTS (
                             SELECT 1 FROM status_reactions own_reactions
                             WHERE own_reactions.account_id = :account_id
                               AND own_reactions.status_id = status_reactions.status_id
                               AND own_reactions.name = status_reactions.name
                               AND own_reactions.custom_emoji_id IS NOT DISTINCT FROM status_reactions.custom_emoji_id
                           ) AS me
                         SQL
                       end

      records = where(status_id: status_ids)
        .group(:status_id, :name, :custom_emoji_id)
        .select(select_values)
        .order(Arel.sql('MIN(status_reactions.created_at), MIN(status_reactions.id)'))
        .to_a

      ActiveRecord::Associations::Preloader.new(records: records, associations: :custom_emoji).call
      records.group_by(&:status_id)
    end
  end

  private

  def valid_reaction_name
    return if custom_emoji.present?
    return if ReactionValidator::SUPPORTED_EMOJIS.include?(name)

    errors.add(:name, I18n.t('reactions.errors.unrecognized_emoji'))
  end

  def schedule_status_update
    key = "status-reaction-update:#{status_id}"
    return unless redis.set(key, 1, nx: true, ex: 2)

    DistributionWorker.perform_in(2.seconds, status_id, { 'update' => true, 'skip_notifications' => true })
  end
end
