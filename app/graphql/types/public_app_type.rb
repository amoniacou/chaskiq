# frozen_string_literal: true

module Types
  class PublicAppType < Types::BaseObject
    field :key, String, null: true
    field :name, String, null: true
    field :tagline, String, null: true
    field :domain_url, String, null: true
    field :active_messenger, Boolean, null: true
    field :theme, String, null: true
    field :customization_colors, Types::JsonType, null: true
    field :reply_time, String, null: true
    field :inbound_settings, Types::JsonType, null: true
    field :email_requirement, String, null: true
    field :greetings, String, null: true
    field :intro, String, null: true
    field :user_tasks_settings, Types::JsonType, null: true
    field :lead_tasks_settings, Types::JsonType, null: true
    field :inline_new_conversations, Boolean, null: true
    field :home_apps, [Types::JsonType], null: true
    field :searcheable_fields, [Types::JsonType], null: true
    field :privacy_consent_required, String, null: true

    field :user_editor_settings, AnyType, null: true
    field :lead_editor_settings, AnyType, null: true

    field :new_conversation_bots, Types::JsonType, null: true
    def new_conversation_bots
      availability = object.in_business_hours?(Time.zone.now)
      object.bot_tasks.get_welcome_bots_for_user(current_user, availability)
    end

    field :app_package, Types::AppPackageIntegrationType, null: true do
      argument :id, String, required: true, default_value: ""
    end

    def app_package(id:)
      # object.app_package_integrations.find(id)
      # object.app_packages.find_by(name: id)
      object.app_package_integrations
            .joins(:app_package)
            .find_by("app_packages.name": id)
    end

    def home_apps
      return object.visitor_home_apps if current_user.is_a?(Visitor)

      object.user_home_apps
    end

    def active_messenger
      ActiveModel::Type::Boolean.new.cast(object.active_messenger)
    end

    def inline_new_conversations
      ActiveModel::Type::Boolean.new.cast(object.inline_new_conversations)
    end

    field :tasks_settings, Types::JsonType, null: true
    def tasks_settings
      if context[:get_app_user].call.is_a?(AppUser)
        object.user_tasks_settings
      else
        object.lead_tasks_settings
      end
    end

    field :available_languages, [Types::JsonType], null: true
    def available_languages
      authorize! object, to: :show?, with: AppPolicy
      object.translations.map(&:locale)
    end

    field :in_business_hours, Boolean, null: true
    def in_business_hours
      object.in_business_hours?(Time.current)
    end

    field :business_back_in, Types::JsonType, null: true
    def business_back_in
      object.business_back_in(Time.current)
    end

    field :article_settings, Types::ArticleSettingsType, null: true
    def article_settings
      # object.plan.allow_feature!('Articles')
      object.article_settings.presence || object.build_article_settings
    end

    field :logo, String, null: true
    def logo
      default_logo = "https://via.placeholder.com/100x100/000000/FFFFFF/?text=Logo"
      return default_logo if object.logo_blob.blank?

      url = begin
        object.logo.variant(resize_to_limit: [100, 100]).processed
      rescue StandardError
        nil
      end
      return nil if url.blank?

      begin
        Rails.application.routes.url_helpers.rails_representation_url(
          url # ,
          # only_path: true
        )
      rescue StandardError
        nil
      end
    end

    field :logo_large, String, null: true
    def logo_large
      options = {
        resize_to_limit: [1280, 600],
        crop: [0, 0, 1280, 600],
        saver: { strip: true, quality: 86 }
      }

      return "" if object.logo_blob.blank?

      Rails.application.routes.url_helpers.rails_representation_url(
        object.logo.variant(options).processed,
        only_path: true
      )
    end

    field :banner, Types::JsonType, null: true do
      argument :id, String, required: true, default_value: ""
    end
    def banner(id:)
      object.banners
            .enabled
            .in_time
            .find_by(id: id)
            .as_json(only: %i[id html_content serialized_content], methods: [:banner_data])
    end
  end
end
