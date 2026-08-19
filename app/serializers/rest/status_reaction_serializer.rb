# frozen_string_literal: true

class REST::StatusReactionSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :name, :count, :me
  attribute :domain, if: :custom?
  attribute :url, if: :custom?
  attribute :static_url, if: :custom?

  def count
    object.respond_to?(:count) ? object.count.to_i : 1
  end

  def me
    object.respond_to?(:me) ? ActiveModel::Type::Boolean.new.cast(object.me) : current_user&.account_id == object.account_id
  end

  def domain
    object.custom_emoji.domain
  end

  def url
    full_asset_url(object.custom_emoji.image.url)
  end

  def static_url
    full_asset_url(object.custom_emoji.image.url(:static))
  end

  def custom?
    object.custom_emoji.present?
  end
end
