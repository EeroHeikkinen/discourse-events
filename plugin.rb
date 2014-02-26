# name: Events
# about: plugin for events
# version: 0.1
# authors: Eero Heikkinen

register_asset "javascripts/discourse/templates/discovery/events.js.handlebars"
register_asset "javascripts/discourse/templates/list/event_list_item.js.handlebars"
register_asset "javascripts/discourse/templates/events.js.handlebars"
register_asset "javascripts/discourse/views/list/event_list_item.js"
register_asset "javascripts/discourse/controllers/discovery_events_controller.js"
register_asset "javascripts/events.js"
register_asset "javascripts/fullcalendar.min.js"
register_asset "javascripts/gcal.js"
register_asset "stylesheets/fullcalendar.css"
register_asset "stylesheets/events.css"

gem "google_calendar", "0.3.1"

load File.expand_path("../event.rb", __FILE__)

EventPlugin = EventPlugin

after_initialize do
  Discourse::Application.routes.prepend do
    # AJAX json method on server
    get "category/:category/l/events" => "events#events"
    # events page on client
    get 'events' => 'list#category_latest', defaults: { category: SiteSetting.events_category }
  end

  module EventPlugin
    class Engine < ::Rails::Engine
      engine_name "event_plugin"
      isolate_namespace EventPlugin
    end

    class ::EventsController < ::ApplicationController

      def events
        t = Topic.secured.visible.listable_topics
          .joins(:category)
          .where("categories.slug = '#{params[:category]}'" +
          " AND topics.title not like 'Category definition%'")
          .order("meta_data->'event_time' ASC")
        list = TopicList.new(:latest, current_user, t)   
        render_serialized(list, TopicListSerializer)
      end
    end
  end

  class ::Post
    before_save :sync_event_metadata

    # see: https://github.com/rails/rails/issues/12497
    def add_meta_data(key,value)
      topic = self.topic
      topic.update_attribute('meta_data', (topic.meta_data || {}).merge(key => value))
    end

    def sync_event_metadata
      event = EventPlugin::Event.new(self)

      return unless event.is_event?

      properties = event.options
      if properties["date"]
        properties["date"] = Time.strptime(properties["date"], "%d.%m.%Y")

        if(SiteSetting.googlecalendar_enabled)
          if(properties["time"])
            start_time, end_time = properties["time"].split("-").collect(&:strip)

            if(start_time)
              hours, minutes = start_time.split(":").collect(&:to_i)
              start_time = properties["date"] + hours.hours + minutes.minutes
            else
              start_time = properties["date"]
            end

            if(end_time)
              hours, minutes = end_time.split(":").collect(&:to_i)
            end

            if end_time and hours and minutes
              end_time = properties["date"] + hours.hours + minutes.minutes
            else
              end_time = start_time
            end

            sync_google_calendar(topic.title, start_time, end_time)
          else
            sync_google_calendar(topic.title, properties["date"], properties["date"]+24.hours)
          end          
        end
      end

      properties.each{|key, value| add_meta_data("event_" + key, value)}

    end

    def sync_google_calendar(title, start_time, end_time)
      cal = Google::Calendar.new(:username => SiteSetting.googlecalendar_username,
                           :password => SiteSetting.googlecalendar_password,
                           :app_name => 'Yhteinen-googlecalendar-integration')
      return nil unless title and start_time and end_time
      
      if topic.meta_data && topic.meta_data["calendar_event_id"]
        calendar_event_id = topic.meta_data["calendar_event_id"]
      end

      event = cal.find_or_create_event_by_id(calendar_event_id) do |e|
        e.title = self.topic.title
        e.start_time = start_time
        e.end_time = end_time 
      end

      Rails.logger.info("Updated event #{event}")

      add_meta_data("calendar_event_id", event.id)
    end
  end

  TopicListItemSerializer.class_eval do
      attributes :event_time,
                 :event_date,
                 :event_city,
                 :event_place,
                 :event_excerpt,
                 :calendar_event_id

      def metadata_exists(key)
        object.meta_data and object.meta_data[key]
      end

      def event_date
        object.meta_data["event_date"]
      end

      def include_event_date?
        metadata_exists("event_date")
      end

      def event_time
        object.meta_data["event_time"]
      end

      def include_event_time?
        metadata_exists("event_time")
      end

      def event_city
        object.meta_data["event_city"]
      end

      def include_event_city?
        metadata_exists("event_city")
      end

      def event_place
        object.meta_data["event_place"]
      end

      def include_event_place?
        metadata_exists("event_place")
      end

      def calendar_event_id
        object.meta_data["calendar_event_id"]
      end

      def include_calendar_event_id?
        metadata_exists("calendar_event_id")
      end

      def include_event_excerpt?
        EventPlugin::Event.new(object.posts.by_post_number.first).is_event?
      end

      def event_excerpt
        # strip images
        object.posts.by_post_number.first.try(:excerpt, 220, {strip_links: true, markdown_images:false}).gsub("[image]", "") || nil
      end
    end
end