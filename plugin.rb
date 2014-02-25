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

after_initialize do
  module Events
    class ::EventsController < ::ApplicationController

      def events
        t = Topic.secured.visible.listable_topics
          .joins(:category)
          .where("categories.slug = '#{params[:category]}'" +
          " AND topics.title not like 'Category definition%'")
          .order("meta_data->'event_time' ASC")
        list = TopicList.new(:latest, current_user, t)   
        render_serialized(list, EventListSerializer)
      end
    end

    class ::EventListItemSerializer < ::TopicListItemSerializer
      attributes :event_time,
                 :event_place,
                 :calendar_event_id

      def event_time
        if object.meta_data and object.meta_data["event_time"]
          return object.meta_data["event_time"]
        end
      end

      def event_place
        if object.meta_data and object.meta_data["event_place"]
          return object.meta_data["event_place"]
        end
      end

      def calendar_event_id
        if object.meta_data and object.meta_data["include_calendar_event_id"]
          object.meta_data["calendar_event_id"]
        end
      end

      def include_excerpt?
        true
      end
    end

    class ::EventListSerializer < ::TopicListSerializer
      self.root = "topic_list"
      has_many :topics, serializer: EventListItemSerializer, embed: :objects
    end
  end

  class ::Topic
    before_save :sync_event_metadata

    # see: https://github.com/rails/rails/issues/12497
    def add_meta_data(key,value)
      self.meta_data = (self.meta_data || {}).merge(key => value)
    end

    def sync_event_metadata
      # Read Date, Time, Place and event name from title
      pieces = /\d{1,2}.\d{1,2}(.\d{4})? (\d{2}:\d{2})? ?(.+:) ?(.+)/.match(self.title)

      if(!pieces)
        Rails.logger.info "Couldn't parse #{self.title}"
        return nil 
      end
      Rails.logger.info "Could parse #{self.title}"

      date = pieces[0]
      hours = pieces[2]
      if(hours)
        time = Time.strptime("#{date} #{hours}", "%d.%m.%Y %R")
      else
        time = Time.strptime("#{date}", "%d.%m.%Y")
      end

      return nil unless time

      place = pieces[3][0...-1]
      self.title = pieces[4]

      if(SiteSetting.googlecalendar_enabled)
        sync_google_calendar(title, time)
      end

      add_meta_data("event_time", time)
      if(place)
        add_meta_data("event_place", place)
      end
    end

    def sync_google_calendar(title, time)
      cal = Google::Calendar.new(:username => SiteSetting.googlecalendar_username,
                           :password => SiteSetting.googlecalendar_password,
                           :app_name => 'Yhteinen-googlecalendar-integration')
      return nil unless cal
      
      if meta_data && meta_data["calendar_event_id"]
        calendar_event_id = meta_data["calendar_event_id"]
      end

      event = cal.find_or_create_event_by_id(calendar_event_id) do |e|
        e.title = self.title
        e.start_time = time
        e.end_time = time
      end

      add_meta_data("calendar_event_id", event.id)
    end
  end

  Discourse::Application.routes.prepend do
    get "category/:category/l/events" => "events#events"
    get 'events' => 'list#category_latest', defaults: { category: SiteSetting.events_category }
  end
end