(function() {

  Discourse.Route.buildRoutes(function() {
    var router = this;
    //this.resource('discovery', { path: '/events' }, function() {
      router.route('events', {path: 'events'});
   //});
  });

  Discourse.DiscoveryEventsController = Discourse.DiscoveryTopicsController.extend({
    latest: false,

    footerMessage: function() {
    }.property('allLoaded', 'topics.length'),

    groupedEvents: function() {
      var topics = this.get('topics');
      var now = new Date();
      var grouped = _.groupBy(topics, function(e) {
        if(new Date(e.event_date) < now)
          return I18n.t("past_events");
        return Discourse.Formatter.shortDate(e.event_date);
      });

      // Need an array to play nice with Ember
      return _.map(grouped, function(topics, grouping){
        return { grouping: grouping, topics: topics };
      });
    }.property('topics')

  });


  Discourse.EventsRoute = Discourse.Route.extend({
    model: function(params) {
      PreloadStore.remove("topic_list");
      return Discourse.Category.findBySlug("uncategorized");
    },

    afterModel: function(model) {
      var self = this,
          noSubcategories = true,
          filter = "latest",
          filterMode = "category/" + Discourse.Category.slugFor(model) + (noSubcategories ? "/none" : "") + "/l/" + "filter",
          listFilter = "category/" + Discourse.Category.slugFor(model) + "/l/" + filter;

      this.controllerFor('search').set('searchContext', model.get('searchContext'));

      var opts = { category: model, filterMode: filterMode };
      opts.noSubcategories = true
      opts.canEditCategory = Discourse.User.currentProp('staff');
      this.controllerFor('navigationCategory').setProperties(opts);

      return Discourse.TopicList.list("category/" + Discourse.SiteSettings.events_category + "/l/events").then(function(list) {
        var tracking = Discourse.TopicTrackingState.current();
        if (tracking) {
          tracking.sync(list, listFilter);
          tracking.trackIncoming(listFilter);
        }

        // If all the categories are the same, we can hide them
        var hideCategory = !list.get('topics').find(function (t) { return t.get('category') !== model; });
        list.set('hideCategory', hideCategory);
        self.set('topics', list);
      });
    },
    
    setupController: function(controller, model) {
      var topics = this.get('topics'),
          filter = 'latest',
          period = filter.indexOf('/') > 0 ? filter.split('/')[1] : '',
          filterText = I18n.t('filters.' + filter.replace('/', '.') + '.title', {count: 0});

      Discourse.set('title', I18n.t('filters.with_category', { filter: filterText, category: model.get('name').capitalize() }));

      this.controllerFor('navigationCategory').set('canCreateTopic', topics.get('can_create_topic'));
      this.controllerFor('discoveryEvents').setProperties({
        model: topics,
        category: model,
        period: period,
        noSubcategories: true
      });

      this.set('topics', null);
    },

    renderTemplate: function() {
      this.render('events', { controller: 'discovery'} );
      this.render('navigation/category', { into: 'events', outlet: 'navigation-bar' });
      this.render('discovery/events', { into: 'events', controller: 'discoveryEvents', outlet: 'list-container' });
    },

    deactivate: function() {
      this._super();
      this.controllerFor('search').set('searchContext', null);
    },

    actions: {
      createTopic: function() {
        var user = this.modelFor('user');
        return this.controllerFor('composer').open({
          action: Discourse.Composer.PRIVATE_MESSAGE,
          usernames: 'eero',
          archetypeId: 'private_message',
          draftKey: 'new_private_message'
        });
      }
    }
  })

  Discourse.EventListItemView = Discourse.TopicListItemView.extend({
    templateName: 'list/event_list_item',
  });

  Handlebars.registerHelper('calendarBlock', function() {
    var url = Discourse.SiteSettings.googlecalendar_url;
    if(!url) return '';
    return new Handlebars.SafeString(
      '<div id="events-calendar"></div>'+
      '<script>$(function() {'+
      '  $("#events-calendar").fullCalendar({ events: "' + url + '", titleFormat: {month: "MMMM"}});'+
      '});</script>'
    );
  });

  /*Handlebars.registerHelper('calendarBlock', function() {
    var url = Discourse.SiteSettings.googlecalendar_url;
    if(!url) return '';
    return new Handlebars.SafeString(
      '<div id="events-calendar"></div>'+
      '<script>$(function() {'+
      '  $("#events-calendar").fullCalendar({ events: "' + url + '", titleFormat: {month: "MMMM"},
        monthNames: ["Tammikuu", 'February', 'March', 'April', 'May', 'June', 'July',
 'August', 'September', 'October', 'November', 'December']});'+
      '});</script>'
    );
  });*/


}).call(this);