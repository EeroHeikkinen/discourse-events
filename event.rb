module ::EventPlugin

  class Event
    def initialize(post)
      @post = post
    end

    def properties
      ['place', 'time', 'city', 'date']
    end

    def prefixes
      Hash[properties.map{|item| [item, I18n.t('events.prefix.'+item)]}]
    end

    def is_event?
      if !@post.post_number.nil? and @post.post_number > 1
        # Not a new post, and also not the first post.
        return false
      end

      topic = @post.topic

      # Topic is not set in a couple of cases in the Discourse test suite.
      return false if topic.nil?

      if @post.post_number.nil? and topic.highest_post_number > 0
        # New post, but not the first post in the topic.
        return false
      end

      # All topics in events category are events
      if topic.category and topic.category.slug == SiteSetting.events_category
        return true
      end

      topic.title.start_with?(I18n.t('events.prefix.topic'))
    end

    def options
      cooked = PrettyText.cook(@post.raw, topic_id: @post.topic_id)
      parsed = Nokogiri::HTML(cooked)
      options_list = parsed.css("ul").first
      return unless options_list

      read_properties = {}
      options_list.css("li").each do |i|
        text = i.children.to_s.strip
        properties.each do |key|
          prefix = prefixes[key]
          if text.start_with?(prefix)
            read_properties[key] = text.sub(prefix, '').strip
            break
          end
        end
      end

      read_properties
    end
  end
end
