// This is a roxen module. Copyright � 2001 - 2004, Roxen IS.

#include <module.h>
inherit "module";

//<locale-token project="mod_emit_timerange">LOCALE</locale-token>
//<locale-token project="mod_emit_timerange">SLOCALE</locale-token>
#define SLOCALE(X,Y)  _STR_LOCALE("mod_emit_timerange",X,Y)
#define LOCALE(X,Y)  _DEF_LOCALE("mod_emit_timerange",X,Y)
// end locale stuff

constant cvs_version = "$Id: emit_timerange.pike,v 1.15 2004/07/08 22:08:42 erikd Exp $";
constant thread_safe = 1;
constant module_uniq = 1;
constant module_type = MODULE_TAG;
constant module_name = "Tags: Calendar tools";
constant module_doc  = "This module provides the emit sources \"timerange\" and"
" \"timezones\" and the scope \"calendar\".";

#ifdef TIMERANGE_VALUE_DEBUG
#define DEBUG(X ...) report_debug( X )
#else
#define DEBUG(X ...)
#endif

// <emit source="timerange"
//   {from|to}-{date|time|{year/month/week/day/hour/minute/second}}="date/time specifier"
//   unit="{year/month/week/day/hour/minute/second}"
//   [calendar="{ISO/...}"]
// > &_.week.day.name; and so on from the look of the below scope_layout </emit>

static constant units =        ({ "Year", "Month", "Week", "Day",
				  "Hour", "Minute", "Second" });
static constant calendars =    ({ "ISO", "Gregorian", "Julian", "Coptic",
				  "Islamic", "Discordian", "unknown" });
static constant output_units = ({ "years", "months", "weeks", "days",
				  "hours", "minutes", "seconds", "unknown" });
// output_unit_no is used for the comparing when using query attribute.
static constant ouput_unit_no = ({ 3,6,0,9,12,15,18,0 });
static constant scope_layout = ([ // Date related data:
			 "ymd"      : "format_ymd",
			 "ymd_short": "format_ymd_short",
			 "date"			: "format_ymd",
			 "year"			: "year_no",
			 "year.day"		: "year_day",
			 "year.name"		: "year_name",
			 "year.is-leap-year"	: "p:leap_year", // predicate
			 "month"		: "month_no",
			 "months"		: "month_no:%02d",
			 "month.day"		: "month_day",
			 "month.days"		: "month_day:%02d",
			 "month.name"		: "month_name",
			 "month.short-name"	: "month_shortname",
			 "month.number_of_days" : "number_of_days",
			 "month.number-of-days" : "number_of_days",
			 "week"			: "week_no",
			 "weeks"		: "week_no:%02d",
			 "week.day"		: "week_day",
			 "week.day.name"	: "week_day_name",
			 "week.day.short-name"	: "week_day_shortname",
			 "week.name"		: "week_name",
			 "day"			: "month_day",
			 "days"			: "month_day:%02d",
			 // Time zone dependent data:
			 "time"			: "format_tod",
			 "timestamp"		: "format_time",
			 "hour"			: "hour_no",
			 "hours"		: "hour_no:%02d",
			 "minute"		: "minute_no",
			 "minutes"		: "minute_no:%02d",
			 "second"		: "second_no",
			 "seconds"		: "second_no:%02d",
			 "timezone"		: "tzname_iso",
			 "timezone.name"	: "tzname",
			 "timezone.iso-name"	: "tzname_iso",
			 "timezone.seconds-to-utc" : "utc_offset",
			 // Misc data:
			 "unix-time"		: "unix_time",
			 "julian-day"		: "julian_day",
			 ""			: "format_nice",
			 // Methods that index to a new timerange object:
			 "next"			: "o:next",
			 "next.second"		: "o:next_second",
			 "next.minute"		: "o:next_minute",
			 "next.hour"		: "o:next_hour",
			 "next.day"		: "o:next_day",
			 "next.week"		: "o:next_week",
			 "next.month"		: "o:next_month",
			 "next.year"		: "o:next_year",
			 "prev"			: "o:prev",
			 "prev.second"		: "o:prev_second",
			 "prev.minute"		: "o:prev_minute",
			 "prev.hour"		: "o:prev_hour",
			 "prev.day"		: "o:prev_day",
			 "prev.week"		: "o:prev_week",
			 "prev.month"		: "o:prev_month",
			 "prev.year"		: "o:prev_year",
			 "this"			: "o:same",
			 "this.second"		: "o:this_second",
			 "this.minute"		: "o:this_minute",
			 "this.hour"		: "o:this_hour",
			 "this.day"		: "o:this_day",
			 "this.week"		: "o:this_week",
			 "this.month"		: "o:this_month",
			 "this.year"		: "o:this_year",
			 // Returns the current module default settings
			 "default.calendar"	: "q:calendar",
			 "default.timezone"	: "q:timezone",
			 "default.timezone.region":"TZ:region",
			 "default.timezone.detail":"TZ:detail",
			 "default.language"	: "q:language" ]);
static constant iso_weekdays = ({ "monday","tuesday",
				  "wednesday","thirsday",
				  "friday","saturday",
				  "sunday"});
static constant gregorian_weekdays = ({ "sunday","monday","tuesday",
					"wednesday","thirsday",
					"friday","saturday"});

static mapping layout;
//! create() constructs this module-global recursive mapping,
//! with one mapping level for each dot-separated segment of the
//! indices of the scope_layout constant, sharing the its values.
//! Where collisions occur, such as "week" and "week.name", the
//! resulting mapping will turn out "week" : ([ "" : "week_no",
//! "day" : "week_day" ]).


//! A bunch of auto-generated methods that go from one TimeRange object to
//! another, to facilitate making navigation lists of various sorts et al.
Calendar.TimeRange prev(Calendar.TimeRange t) { return t->prev(); }
Calendar.TimeRange same(Calendar.TimeRange t) { return t; }
Calendar.TimeRange next(Calendar.TimeRange t) { return t->next(); }
function(Calendar.TimeRange:Calendar.TimeRange)
  prev_year,prev_month,prev_week,prev_day,prev_hour,prev_minute,prev_second,
  this_year,this_month,this_week,this_day,this_hour,this_minute,this_second,
  next_year,next_month,next_week,next_day,next_hour,next_minute,next_second;

function(Calendar.TimeRange:Calendar.TimeRange) get_prev_timerange(string Unit)
{ return lambda(Calendar.TimeRange t) { return t - Calendar[Unit]();}; }
function(Calendar.TimeRange:Calendar.TimeRange) get_this_timerange(string unit)
{
#if 0
  if(unit == "day")
    return lambda(Calendar.TimeRange t) { return t->day(1); };
#endif
  return lambda(Calendar.TimeRange t) { return t[unit](); };
}
function(Calendar.TimeRange:Calendar.TimeRange) get_next_timerange(string Unit)
{ return lambda(Calendar.TimeRange t) { return t + Calendar[Unit]();}; }

void create(Configuration conf)
{
  DEBUG("%O->create(%O)\b", this_object(), conf);
  if(layout)
  {
    DEBUG("\b => layout already defined.\n");
    return;
  }

  foreach(units, string Unit)
  {
    string unit = lower_case(Unit);
    this_object()["prev_"+unit] = get_prev_timerange(Unit);
    this_object()["this_"+unit] = get_this_timerange(unit);
    this_object()["next_"+unit] = get_next_timerange(Unit);
  }


  layout = ([]);
  array idx = indices( scope_layout ),
	vals = values( scope_layout );
  for(int i = 0; i < sizeof( scope_layout ); i++)
  {
    array split = idx[i] / ".";
    mapping t1 = layout, t2;
    int j, last = sizeof( split ) - 1;
    foreach(split, string index)
    {
      string|function value = vals[i];
      if(sscanf(value, "o:%s", value))
	value = [function]this_object()[value];
      if(j == last)
	if(t2 = t1[index])
	  if(mappingp(t2))
	    t1[index] += ([ "" : value ]);
	  else
	    t1 += ([ index : value,
		     "" : t2 ]);
	else
	  t1[index] = value;
      else
	if(t2 = t1[index])
	  if(mappingp(t2))
	    t1 = t2;
	  else
	    t1 = t1[index] = ([ "" : t2 ]);
	else
	  t1 = t1[index] = ([]);
      j++;
    }
  }

  int inited_from_scratch = 0;
  if(!calendar)
    inited_from_scratch = !!(calendar = Calendar.ISO_UTC);

  defvar("calendar", Variable.StringChoice("ISO", calendars-({"unknown"}), 0,
	 "Default calendar type", "When no other calendar type is given, the "
	 "rules of this calendar will be used. This also defines the calendar "
	 "used for the calendar scope."))->set_changed_callback(lambda(object c)
	 { calendar = calendar->set_calendar(c->query()); });

  // Could perhaps be done as a two-level widget for continent/region too using
  // sort(Array.uniq(column(map(Calendar.TZnames.zonenames(),`/,"/"),0))), but
  // where does UTC fit in that scheme? Nah, let's keep it simple instead:
  defvar("timezone", TZVariable("UTC", 0, "Default time zone",
	 "When no other time zone is given, this time zone will be used. "
	 "This also defines the time zone for the calendar scope. Some "
	 "examples of valid time zones include \"Europe/Stockholm\", \"UTC\", "
	 "\"UTC+3\" and \"UTC+10:30\"."))->set_changed_callback(lambda(object t)
	 { calendar = calendar->set_timezone(t->query()); });

  array known_languages = filter(indices(Calendar.Language), is_supported);
  known_languages = sort(map(known_languages, wash_language_name));
  defvar("language", Variable.StringChoice("English", known_languages, 0,
					   "Default calendar language",
	 "When no other language is given, this language will be used. "
	 "This also defines the language for the calendar scope.\n"))
	 ->set_changed_callback(lambda(Variable.Variable language)
	 {
	   calendar = calendar->set_language(language->query());
	 });

  defvar ("db_name",
          Variable.DatabaseChoice( "timerange_"+
          (conf ? Roxen.short_name(conf->name):""),
          0, "TimeRange module database")->set_configuration_pointer( my_configuration ) );

  if(inited_from_scratch)
  {
    calendar = Calendar[query("calendar")]
	     ->set_timezone(query("timezone"))
	     ->set_language(query("language"));
  }

  DEBUG("\b => layout: %O.\n", layout);
}

int is_supported(string class_name)
{ return sizeof(array_sscanf(class_name, "c%[^_]") * "") > 3; }

string wash_language_name(string class_name)
{ return String.capitalize(lower_case(class_name[1..])); }

int is_valid_timezone(string tzname)
{ return (Calendar.Timezone[tzname])? 1 : 0; }

class TZVariable
{
  inherit Variable.String;

  array(string) verify_set_from_form( mixed new )
  {
    if(is_valid_timezone( [string]new ))
      return ({ 0, [string]new - "\r" - "\n" });
    return ({ "Unknown timezone " + [string]new, query() });
  }
}

class TagIfIsValidTimezone
{
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "is-valid-timezone";

  int(0..1) eval(string tzname, RequestID id)
  {
    return is_valid_timezone(tzname);
  }
}

object calendar; // the default calendar

void start()
{
  query_tag_set()->prepare_context = set_entities;
}

string status()
{
  return sprintf("Calendar: %O<br />\n", calendar);
}

void set_entities(RXML.Context c)
{
  c->add_scope("calendar", TimeRangeValue(calendar->Second(c->id->time),
					  "second", ""));
}

//! Plays the role as both an RXML.Scope (for multi-indexable data
//! such as scope.year.is-leap-year and friends) and an RXML.Value for
//! the leaves of all such entities (as well as the one-dot variables,
//! for example scope.julian-day).
class TimeRangeValue(Calendar.TimeRange time,	// the time object we represent
		     string type,		// its type ("second"..."year")
		     string parent_scope)	// e g "" or "calendar.next"
{
  inherit RXML.Scope;

  //! Once we have the string pointing out the correct time object
  //! method, this method calls it from the @code{time@} object and
  //! returns the result, properly quoted.
  //! @param calendar_method
  //!   the name of a method in a @[Calendar.TimeRange] object,
  //!   possibly prefixed with the string @tt{"p:"@}, which signifies
  //!   that the function returns a boolean answer that in RXML should
  //!   return either of the strings @tt{"yes"@} or @tt{"no"@}.
  static string fetch_and_quote_value(string calendar_method,
				      RXML.Type want_type)
  {
    string result, format_string;
    if(sscanf(calendar_method, "TZ:%s", calendar_method))
    {
      result = query("timezone");
      if(calendar_method == "region")
	sscanf(result, "%[^-+/ ]", result);
      else if(has_value(result, "/"))
	sscanf(result, "%*s/%s", result);
    }
    else if(sscanf(calendar_method, "q:%s", calendar_method))
      result = query(calendar_method);
    else if(sscanf(calendar_method, "p:%s", calendar_method))
      result = time[ calendar_method ]() ? "yes" : "no";
    else if(sscanf(calendar_method, "%s:%s", calendar_method, format_string))
      result = sprintf(format_string, time[ calendar_method ]());
    else
      result = (string)time[ calendar_method ]();
    if(want_type && want_type != RXML.t_text)
      result = want_type->encode( result );
    DEBUG("\b => %O\n", result);
    return result;
  }

  //! Trickle down through the layout mapping, fetching whatever the
  //! scope � var variable name points at there. (Once the contents of
  //! the layout mapping is set in stone, the return type can safely
  //! be strictened up a bit ("string" instead of "mixed", perhaps).
  static mixed dig_out(string scope, string|void var)
  {
    mixed result = layout;
    string reached;
    foreach((scope/".")[1..] + (var ? ({ var }) : ({})), string index)
      if(!mappingp(result))
	RXML.run_error(sprintf("Can't sub-index %O with %O.\n",
			       reached || "", index));
      else if(!(result = result[ index ]))
      {
	DEBUG("\b => ([])[0] (no such scope:%O%s)\n",
	      scope, (zero_type(var) ? "" : sprintf(", var:%O combo", var)));
	return ([])[0];
      }
      else
	reached = (reached ? reached + "." : "") + index;
    return result;
  }

  //! Called for each level towards the leaves, including the leaf itself.
  mixed `[](string var, void|RXML.Context ctx,
	    void|string scope, void|RXML.Type want_type)
  {
    DEBUG("%O->`[](var %O, ctx %O, scope %O, type %O)\b",
	  this_object(), var, ctx, scope, want_type);
    RequestID id = ctx->id; NOCACHE();

    // If we further down decide on creating a new TimeRangeValue, this will
    // be its parent_scope name; let's memorize instead of reconstruct it:
    string child_scope = scope;

    // Since we might have arrived at this object via a chain of parent objects,
    // e g "calendar.next.year.next.day" (which would entitle us a parent_scope
    // of "calendar.next.year.next"), we must cut off all the already processed
    // chunks who led the path here:
    if(scope == parent_scope)
      scope = (parent_scope / ".")[-1];
    else
      sscanf(scope, parent_scope + ".%s", scope);

    string|mapping|function what;
    if(!(what = dig_out(scope, var)))
      return ([])[0]; // conserve zero_type
    //report_debug("scope: %O, var: %O, what: %t\n", scope, var, what);
    if(functionp( what )) // it's a temporal method to render us a new TimeRange
    {
      //report_debug("was: %O became: %O\n", time, what(time));
      object result = TimeRangeValue(what(time), type, child_scope);
      DEBUG("\b => new %O\n", result);
      return result;
    }
    if(what && stringp( what )) // it's a plain old Calendar method name
      return fetch_and_quote_value([string]what, want_type);
    DEBUG("\b => same object\n",);
    return this_object();
  }

  //! Called to dereference the final leaf of a variable entity, i e var=="leaf"
  //! and scope=="node.[...].node" for the entity "&node.[...].node.leaf;". This
  //! step is however skipped when `[] returned an already quoted value rather
  //! than an object.
  mixed rxml_var_eval(RXML.Context ctx, string var,
		      string scope, void|RXML.Type want_type)
  {
    DEBUG("%O->rxml_var_eval(ctx %O, var %O, scope %O, type %O)\b",
	  this_object(), ctx, var, scope, want_type);
    RequestID id = ctx->id; NOCACHE();

    // Just as in `[], we might have arrived via some parent. In the specific
    // case that we arrived via `[], and got called with the same parameters as
    // we were there (e g when resolving "&calendar.next.day;"; i e there was
    // nothing, "", to lookup in the new object).
    if(scope == parent_scope)
    {
      scope = var;
      var = "";
    }
    else // this typically happens for scope "calendar.default", var "timezone":
      sscanf(scope, parent_scope + ".%s", scope);

    mixed what, result;
    if(!(what  = dig_out(scope, var)))
    {
      DEBUG("\b => ([])[0] (what conserved)\n");
      return ([])[0]; // conserve zero_type
    }
    if(mappingp( what ) && !(result = what[""])) // may use this scope as a leaf
    { // this probably only occurs if the layout mapping is incorrectly set up:
      DEBUG("\b => ([])[0] (what:%O)\n", what);
      return ([])[0];
    }
    return fetch_and_quote_value(result || what, want_type);
  }

  array(string) _indices(void|RXML.Context ctx, void|string scope_name)
  {
    DEBUG("%O->_indices(%s)\b", this_object(),
	  zero_type(ctx) ? "" : zero_type(scope_name) ?
	  sprintf("ctx: %O, no scope", ctx) :
	  sprintf("ctx: %O, scope %O", ctx, scope_name));
    mapping layout = scope_name ? dig_out(scope_name) : scope_layout;
    DEBUG("\b => %O", layout && indices(layout));
    return layout && indices(layout);
  }

  //! called with 'O' and ([ "indent":2 ]) for <insert variables=full/>, which
  //! is probably a bug, n'est-ce pas? Shouldn't this be handled just as with
  //! the normal indexing, using `[] / rxml_var_eval (and possibly cast)?
  string _sprintf(int|void sprintf_type, mapping|void args)
  {
    switch( sprintf_type )
    {
      case 't': return sprintf("TimeRangeValue(%s)", type);
      case 'O':
      default:
	return sprintf("TimeRangeValue(%O/%O)", time, parent_scope);
    }
  }
}

Calendar get_calendar(string name)
{
  if(!name)
    return calendar;
  string wanted = calendars[search(map(calendars, upper_case),
				   upper_case(name))];
  if(wanted == "unknown")
    RXML.parse_error(sprintf("Unknown calendar %O.\n", name));
  return Calendar[wanted];
}

class TagEmitTimeZones
{
  inherit RXML.Tag;
  constant name = "emit", plugin_name = "timezones";

  mapping(string:mapping(string : Calendar.TimeRange)) zones;

  Calendar.TimeRange get_time_in_timezone(Calendar.TimeRange time,
					  string tzname, string region)
  {
    Calendar.TimeRange q = time->set_timezone(tzname),
		      ds = Calendar.Events.tzshift->next(q); // next (non|)dst
    if(ds && (!zones[region]->next_shift || (zones[region]->next_shift < ds)))
      zones[region]->next_shift = ds;
    return q;
  }

  void refresh_zones(Calendar.TimeRange time, string|void region)
  {
    if(!zones) zones = ([]);
    if(!region)
    {
      zones->UTC = ([]);
      for(int i=-24; i<=24; i++)
      {
	string offset = sprintf("UTC%+03d:%02d", i/2, i%2*30);
	zones->UTC[offset] = get_time_in_timezone(time, offset, "UTC");
      }
      foreach((array)Calendar.TZnames.zones, [region, array z])
      {
	zones[region] = ([]);
	foreach(z, string s)
	  zones[region][s] = get_time_in_timezone(time, region+"/"+s, region);
      }
    }
    else if(region != "UTC")
      foreach(Calendar.TZnames.zones[region], string z)
	zones[region][z] = get_time_in_timezone(time, region+"/"+z, region);
  }

  void create() { refresh_zones(get_calendar(query("calendar"))->Second()); }

  array get_dataset(mapping args, RequestID id)
  {
    NOCACHE();
    string region = m_delete(args, "region");
    if(!region)
      return map(sort(indices(zones)),
		 lambda(string region) { return ([ "name":region ]); });
    Calendar cal = get_calendar(m_delete(args, "calendar"));
    Calendar.TimeRange time, next_shift;
    if(!(time = get_date("", args, cal)))
      time = cal->Second();
    if(!zones[region])
      RXML.parse_error(sprintf("Unknown timezone region %O.\n", region));
    next_shift = zones[region] && zones[region]->next_shift;
    if(next_shift && time > next_shift)
      refresh_zones(time, region);
    return map(sort(indices(zones[region]) - ({ "next_shift" })),
	       lambda(string place)
	       {
		 return ([ "name" : place ]) +
		   scopify(zones[region][place], "second");
	       });
  }
}

class TagEmitTimeRange
{
  inherit RXML.Tag;
  constant name = "emit", plugin_name = "timerange";

  array get_dataset(mapping args, RequestID id)
  {
    // DEBUG("get_dataset(%O, %O)\b", args, id);
    // Start Eriks stuff, july 8 2004
    string plugin;
    RoxenModule provider;
    if(plugin = m_delete(args, "plugin")) {
      array(RoxenModule) data_providers = id->conf->get_providers("timerange-plugin");
      foreach(data_providers, RoxenModule prov) {
	if(prov->supplies_plugin_name && prov->supplies_plugin_name(plugin)) {
	  provider = prov;
	  break;
	}
      }
      if(provider) {
	werror(sprintf("We have a provider: %O\n", provider));


      } else {
	RXML.run_error(sprintf("Timerange %s plugin does not exist", plugin));
      }
    }
    // End Eriks stuff, july 8 2004
    string cal_type = args["calendar"];
    Calendar cal = get_calendar(m_delete(args, "calendar"));
    Calendar.TimeRange from, to, range;
    string what, output_unit;
    int compare_num, unit_no;
    if(what = m_delete(args, "unit"))
    {
      output_unit = output_units[search(output_units, what)];
      if(output_unit == "unknown")
	RXML.parse_error(sprintf("Unknown unit %O.\n", what));

      unit_no = search(output_units, what);
      compare_num = ouput_unit_no[unit_no];

      from = to = get_date("", args, cal);
      from = get_date("from", args, cal) || from || cal->Second();

      int weekday_needed, change_to;

      if((what = m_delete(args, "from-week-day")) && from)
      {
        what = lower_case(what);
        if(search(gregorian_weekdays,lower_case(what)) == -1)
          RXML.parse_error(sprintf("Unknown day: %O\n",what));
        int weekday = from->week_day();

        if(from->calendar() != Calendar.ISO){
          weekday_needed = search(gregorian_weekdays,what)+1;
	}
        else
          weekday_needed = search(iso_weekdays,what)+1;
        if (weekday < weekday_needed)
          change_to = 7 - (weekday_needed - weekday);
        else if(weekday > weekday_needed)
          change_to = weekday - weekday_needed;
        if (change_to > 0)
          from = from - change_to;
      }

      to = get_date("to", args, cal) || to || from;

      if(what = m_delete(args, "to-week-day")){
	what = lower_case(what);
	if(search(gregorian_weekdays,what) == -1)
	  RXML.parse_error(sprintf("Unknown day: %O\n",what));
	change_to = 0;
	weekday_needed = 0;
	int weekday = to->week_day();
	if(to->calendar() != Calendar.ISO)
	  weekday_needed = search(gregorian_weekdays,what)+1;
	else
	  weekday_needed = search(iso_weekdays,what)+1;

	if (weekday < weekday_needed)
	  change_to = weekday_needed - weekday;
	else if(weekday > weekday_needed)
	  change_to = 7 - (weekday - weekday_needed);
	if (change_to > 0)// && upper_case(to->week_day_name()) != upper_case(what) - NOT NEEDED
	{
	  if(to == to->calendar()->Year())
	    to = to->calendar()->Day() + change_to;
	  else
	    to += change_to;
	}
      }

      if((what = m_delete(args, "from-week-day")) && from)
			{
        what = lower_case(what);
        if(search(gregorian_weekdays,lower_case(what)) == -1)
          RXML.parse_error(sprintf("Unknown day: %O\n",what));
        int weekday_needed, change_to;
        int weekday = from->week_day();

        if(calendar != "ISO")
          weekday_needed = search(gregorian_weekdays,what)+1;
        else
          weekday_needed = search(iso_weekdays,what)+1;
        if (weekday < weekday_needed)
          change_to = 7 - (weekday_needed - weekday);
        else if(weekday > weekday_needed)
          change_to = weekday - weekday_needed;
        if (change_to > 0)
          from = from - change_to;
      }

      if((what = m_delete(args, "to-week-day")))
      {
	what = lower_case(what);
	if(search(gregorian_weekdays,what) == -1)
	  RXML.parse_error(sprintf("Unknown day: %O\n",what));
	int change_to = 0, weekday_needed = 0;
	int weekday = to->week_day();
	if(calendar != "ISO")
	  weekday_needed = search(gregorian_weekdays,what)+1;
	else
	  weekday_needed = search(iso_weekdays,what)+1;

	if (weekday < weekday_needed)
	  change_to = weekday_needed - weekday;
	else if(weekday > weekday_needed)
	  change_to = 7 - (weekday - weekday_needed);
	if (change_to > 0)
	  if(to == to->calendar()->Year())
	    to = to->calendar()->Day() + change_to;
	  else
	    to += change_to;
      }

      string range_type = m_delete(args, "inclusive") ? "range" : "distance";
      if(from <= to)
	range = from[range_type]( to );
      else
	range = to[range_type]( from );
    }
    else
      range = get_date("", args, cal) || cal->Second();

    if(what = m_delete(args, "output-timezone"))
      range = range->set_timezone( what );

    if(what = m_delete(args, "language"))
      range = range->set_language( what );

    array(Calendar.TimeRange) dataset;
    if(output_unit)
    {
      dataset = range[output_unit](); // e g: r->hours() or r->days()
      output_unit = output_unit[..sizeof(output_unit)-2]; // lose plural "s"
    }
    else
    {
      dataset = ({ range }); // no unit, from and to given: do a single pass
      output_unit = "second";
    }

    if(from > to)
      dataset = reverse( dataset );

    array(Calendar.TimeRange | mapping | array) dset = ({});
    array(string) sqlindexes;

    if(args["query"]){
      string sqlquery = m_delete(args,"query");
      string use_date = m_delete(args,"compare-date");
      if(!use_date)
        RXML.run_error("No argument compare-date. The compare-date attribute "
                       "is needed together with the attribute query!\n");

      string host = m_delete(args,"host");
      //werror(sprintf("QUERY : %O HOST: %O\n",sqlquery,host));

      array(mapping) rs = db_query(sqlquery,host||query("db_name")||"none");
      if(sizeof(rs) > 0)
      {
        sqlindexes = indices(rs[0]);
        foreach(dataset,Calendar.TimeRange testing)
        {
	  int i = 0;
	  int test = 1;

	  foreach(rs,mapping rsrow)
	  {
            if(testing->format_time()[..compare_num] == rsrow[use_date])
            {
	      dset += ({({testing, rsrow})});
	      test = 0;
	    }
            i++;
          }

	  if(test == 1)
	    dset += ({testing});
	} //End foreach
      }
    }// End if we have a SQL query

#ifndef RXML_FUTURE_COMPAT
    RXML.Tag emit = id->conf->rxml_tag_set->get_tag("emit");
    args = args - emit->req_arg_types - emit->opt_arg_types;
    if(sizeof( args ))
      RXML.parse_error(sprintf("Unknown attribute%s %s.\n",
			       (sizeof(args)==1 ? "" : "s"),
			       String.implode_nicely(indices(args))));
#endif

  array(mapping) res;

  if(sizeof(dset) > 0){
    res = ({});
    for(int i = 0;i<sizeof(dset);i++)
      {
        if(arrayp(dset[i]))
          {
            //werror(sprintf("dset[%O][0]: %O\n",i,dset[i][0]));
            res += ({ scopify(dset[i][0], output_unit) + dset[i][1] });
            //werror(sprintf("dset[%O][1]: %O\n",i,dset[i..]));
          }
        else
          res += ({ scopify(dset[i], output_unit) });
      }
  }
  else
    res = map(dataset, scopify, output_unit);
  // DEBUG("\b => %O\n", res);
  return res;
  }
}

mapping scopify(Calendar.TimeRange time, string unit, string|void parent_scope)
{
  TimeRangeValue value = TimeRangeValue(time, unit, parent_scope || "");
  return mkmapping(indices( layout ),
		   allocate(sizeof( layout ), value));
}

Calendar.TimeRange get_date(string name, mapping args, Calendar calendar)
{
  if(name != "")
    name = name + "-";
  Calendar cal = calendar; // local copy
  Calendar.TimeRange date; // carries the result
  string what; // temporary data
  if(what = m_delete(args, name + "timezone"))
    cal = cal->set_timezone( what );
  if(what = m_delete(args, name + "language"))
    cal = cal->set_language( what );

  int(0..1) succeeded = 1;
  if(what = m_delete(args, name + "time"))
  {
    if(catch(date = cal->dwim_time( what )))
      if(catch(date = cal->dwim_day( what )) || !date)
	RXML.run_error(sprintf("Illegal %stime %O.\n", name, what));
      else
	date = date->second();
  }
  else if(what = m_delete(args, name + "date"))
  {
    if(catch(date = cal->dwim_day( what )))
      RXML.run_error(sprintf("Illegal %sdate %O.\n", name, what));
  }
  else if(what = m_delete(args, name + "year"))
    date = cal->Year( (int)what );
  else
    succeeded = !(date = cal->Year());

  // we have at least a year; let's get more precise:
  foreach(units[1..], string current_unit)
  {
    string unit = lower_case( current_unit );
    if(what = m_delete(args, name + unit))
    {
      succeeded = 1;
      date = date[unit]( (int)what );
      DEBUG("unit: %O => %O (%d)\n", unit, what, (int)what);
    }
  }
  return succeeded && date->set_timezone(calendar->timezone())
			  ->set_language(calendar->language());
}

array(mapping) db_query(string q,string db_name)
{
  mixed error;
  Sql.sql con;
  array(mapping(string:mixed))|object result;
  error = catch(con = DBManager.get(db_name,my_configuration(),0));
  if(!con)
    RXML.run_error("Couldn't connect to SQL server"+
                 (error?": "+error[0]:"")+"\n");
  else
  {
    if( catch(result = (con->query)(q)) )
    {
      error = con->error();
        if (error) error = ": " + error;
          error = sprintf("Query failed%s\n", error||".");
        RXML.parse_error(error);
    }
  }
  return con->query(q);
}



TAGDOCUMENTATION;
constant tagdoc = ([
      "emit#timerange": ({ #"<desc type='plugin'>
  <p>This tag emits over a timerange
  between two dates (from i.e. from-date and to-date -attributes). 
  The purpose is also that you might have a Resultset from i.e. a
  database (but the goal is that   it should work with other resultsets
  why not from an ldap search?) and each
  row in the database result will also contain corresponding dates.
  But if there is no result row from the database query that match one
  day the variables from the Resultset will be empty.
  </p>
  <p>
  This tag is very usefull for application that needs a calendar functionality.
  </p>
  <note><p>All <xref href='emit.tag'>emit</xref> attributes apply.</p></note>

  </desc>

  <attr name='unit' value='years|months|weeks|days|hours|minutes|seconds' required='required'>
  <p>years - loop over years<br />
     days - will result in a loop over days<br />
     etc.
  </p>
  </attr>

  <attr name='calendar' value='ISO|Gregorian|Julian|Coptic|Islamic|Discordian' default='ISO'>
    <p>The type of calendar that is recieved from the to-* and from-* attributes and will
       also reflect the values that you get.</p>
    <p>These are not case sensitive values.</p>
  </attr>

  <attr name='from-date' value='YYYY-MM-DD'>
    <p>
      The date that the emit starts at (i.e. '2002-06-21' - which was 
      midsummer eve in Sweden that year)
    </p>
  </attr>

  <attr name='from-year' value='YYYY'>
    <p>
      Start the emit from this year. Used with all the unit types.
    </p>
  </attr>

  <attr name='from-time' value='HH:MM:SS'>
    <p>
      Two digits for hours, minutes and seconds - separated by colon. Usefull when the
      value of unit is hours, minutes or seconds. But it might also influence when
      used with the <att>query</att> attribute.
    </p>
  </attr>

  <attr name='to-date' value='YYYY-MM-DD'>
    <p>
      The date (i.e. '2002-06-21' - which was midsummer eve in Sweden that year)
    </p>
  </attr>

  <attr name='to-year' value='YYYY'>
    <p>
      Emit to this year. Used with all the unit types.
    </p>
  </attr>

  <attr name='to-time' value='HH:MM:SS'>
    <p>
      Two digits for hours, minutes and seconds - separated by colon. 
      Usefull when the value of unit is hours, minutes or seconds. 
      But it might also have impact when used with the query attribute.
    </p>
  </attr>

  <attr name='from-week-day' value='monday|tuesday|wednesday|thirsday|friday|saturday|sunday'>
   <p>Alter the startdate to nearest weekday of the choice which means
      that if you declare in <att>from-date</att> 2002-07-25 which is a
      tuesday the startdate will become
      2002-07-24 when week-start='monday'. So far this is supported by ISO, 
      Gregorian and Julian calendar.</p>
  </attr>

  <attr name='to-week-day' value='monday|tuesday|wednesday|thirsday|friday|saturday|sunday'>
    <p>Alter the <att>to-date</att> to neareast weekday this day or after
       this day depending on where the weekday is. So far this is supported
       by ISO, Gregorian and Julian calendar.</p>
  </attr>

  <attr name='inclusive' value='empty'>
    <p>Affects the <i>to-*</i> attributes so that the <att>to-date</att> 
       will be included
       in the result. See examples below.</p>
  </attr>

  <attr name='query'>
    <p>A sql select query. <i>Must</i> be accompanied by a
       <att>compare-date</att> attribute otherwise it will throw an error.
       The attribute can for now only compare date in
       the ISO date format se <att>compare-date</att> for the ISO format.
    </p>
  </attr>

  <attr name='compare-date' value='sql-column-name'>
    <p>A column - or alias name for a column in the sql select query.
       The value of the column must be of the ISO format corresponding
       to the <att>unit</att> attribute asked for.
    </p>
    <p>
    <xtable>
      <row>
        <h>unit</h> <h>format</h>
      </row>
      <row>
        <c><p> years  </p></c>
        <c><p> YYYY</p></c>
      </row>
      <row>
        <c><p> months </p></c>
        <c><p> YYYY-MM</p></c>
      </row>
      <row>
        <c><p> weeks  </p></c>
        <c><p> has none (for now)</p></c>
      </row>
      <row>
        <c><p> days   </p></c>
        <c><p> YYYY-MM-DD</p></c>
      </row>
      <row>
        <c><p> hours  </p></c>
        <c><p> YYYY-MM-DD HH</p></c>
      </row>
      <row>
        <c><p> minutes</p></c>
        <c><p> YYYY-MM-DD HH:mm</p></c>
      </row>
      <row>
        <c><p> seconds</p></c>
        <c><p> YYYY-MM-DD HH:mm:ss</p></c>
      </row>
    </xtable>
    </p>
    <p>This attribute is <i>mandatory if the <att>query</att>
       attribute exists</i>.
       This attribute does nothing if the query attribute doesn't exists.
    </p>
  </attr>

  <attr name='host' value='db-host-name'>
    <p>
      A databas host name, found under DBs in Administration Interface.
      Used together with <att>query</att> attribute. Look at emit#sql
      for further information.
    </p>
  </attr>

  <attr name='language' value='langcode'>
    <p>
      The language code to use:
    </p>
    <p>
      cat (for catala)<br />
      hrv (for croatian)<br />
      <!-- ces (for czech)-->
      nld (for dutch)<br />
      eng (for english)<br />
      fin (for finnish)<br />
      fra (for french)<br />
      deu (for german)<br />
      hun (for hungarian)<br />
      ita (for italian)<br />
      <!-- jpn (for japanese)-->
      <!-- mri (for maori)-->
      nor (for norwegian)<br />
      pol (for polish)<br />
      por (for portuguese)<br />
      <!-- rus (for russian) -->
      srp (for serbian)<br />
      slv (for slovenian)<br />
      spa (for spanish)<br />
      swe (for swedish)
    </p>
  </attr>

  <ex>
    <emit source='timerange' unit='hours' 
      from-time='08:00:00' to-time='12:00:00' inclusive='1'>
      <div>&_.hour;:&_.minute;:&_.second;</div>
    </emit>
  </ex>
  <ex>
    <emit source='timerange' unit='days'
      from-date='2002-11-23' to-date='2002-12-25' 
      from-week-day='monday' calendar='ISO' to-week-day='sunday' inclusive='1'>
      <if variable='_.week.day is 7'>
        <font color='red'>
          <if sizeof='_.day is 1'>0</if>&_.day;
        </font>
        <br />
      </if>
      <else>
        <if sizeof='_.day is 1'>0</if>&_.day;
      </else>
    </emit>
  </ex>
  <p>Database system this example uses: MySQL</p>
  <p>Database name: mydb </p>
  <p>   Table name: calendar_src:</p>
  <xtable>
    <row>
      <h>name</h> <h>type</h>
    </row>
    <row>
      <c><p> id  </p></c>
      <c><p>INT PRIMARY KEY</p></c>
    </row>
    <row>
      <c><p> start_date  </p></c>
      <c><p> DATETIME </p></c>
    </row>
    <row>
      <c><p> end_date  </p></c>
      <c><p> DATETIME </p></c>
    </row>
    <row>
      <c><p> day_event  </p></c>
      <c><p> TEXT </p></c>
    </row>
  </xtable>
  <ex-box>
    <table border='1'>
      <tr>
        <emit source='timerange'
          unit='days' calendar='ISO'
          from-date='2003-03-01'
          to-date='2003-03-31'
          from-week-day='monday'
          to-week-day='sunday'
          inclusive=''
          query='SELECT day_event,
                 DATE_FORMAT(start_date,\"%Y-%m-%d\") as comp_date
                 FROM calendar_src
                 WHERE start_date &gt; \"2003-03-01 00:00:00\"
                   AND start_date &lt; \"2003-04-01 00:00:00:\"
                 ORDER BY start_date'
          compare-date='comp_date'
          host='mydb'>

          <if variable='_.ymd_short is &var.ymd_short_old;' not=''>
            <![CDATA[</td>]]>
          </if>
          <if variable='_.week.day is 1' 
              match='&_.ymd_short; != &var.ymd_short_old;'>
            <if variable='_.counter &gt; 1'>
              <![CDATA[
              </tr>
              <tr>]]>
            </if>
            <td width='30' valign='top'>
              <div>&_.week;</div>
            </td>
            <![CDATA[<td width='100' valign='top'>]]>
            <div align='right'>&_.month.day;</div>
            <div>&_.day_event;</div>
          </if>
          <else>
            <set variable='var.cal-day-width'
              value='{$working-day-column-width}'/>
            <if variable='_.ymd_short is &var.ymd_short_old;' not=''>
              <![CDATA[<td width='100' valign='top'>]]>
              <if variable='_.week.day is 7'>
                <div align='right' style='color: red'>
                  &_.month.day;
                </div>
              </if>
              <else>
                <div align='right'>&_.month.day;</div>
              </else>
            </if>
            <div>&_.day_event;</div>
          </else>
          <set variable='var.ymd_short_old' from='_.ymd_short'/>
        </emit>
      </tr>
    </table>
  </ex-box>
  <p>The code above does not work in a XML- or XSLT-file
    unless modified to conform to XML. To accomplish that
    &lt;xsl:text disable-output-escaping='yes'&gt;
    &lt;![CDATA[&lt;td&gt;]]&gt;
    &lt;/xsl:text&gt; will solve that. Or it could be placed
    in a RXML-variable: &lt;set variable='var.start_td'
    value='&amp;lt;td&amp;gt;'/&gt; and used:
    &amp;var.start_td:none; see documentation: Encoding,
    under Variables, Scopes &amp; Entities
    </p>
  ",
  ([
    "&_.year;":#"<desc type='entity'><p>
  Returns the year i.e. 2003</p></desc>",
  "&_.year.day;":#"<desc type='entity'><p>
  Returns the day day of the year for date,
  in the range 1 to 366</p></desc>",

    "&_.year.name;":#"<desc type='entity'><p>
  Returns the year number i.e. 2003</p></desc>",

    "&_.year.is-leap-year;":#"<desc type='entity'><p>
  Returns TRUE or FALSE</p></desc>",

    "&_.month;":#"<desc type='entity'><p>
  Returns the month number i.e. 3 for march</p></desc>",

    "&_.month.day;":#"<desc type='entity'><p>
  Returns the day number in the month</p></desc>",

    "&_.month.number_of_days;":#"<desc type='entity'><p>
  Returns the number of days there is in a month.</p></desc>",

    "&_.month.name;":#"<desc type='entity'><p>
  Month name. Language dependent.</p></desc>",

    "&_.month.short-name;":#"<desc type='entity'><p>
  Month short name. Language dependent.</p></desc>",

    "&_.month.number-of-days;":#"<desc type='entity'><p>
  Integervalue of how many days the month contains. <ent>_.month.number_of_days</ent>
  will also work due to backward compatibility.</p></desc>",

    "&_.week;":#"<desc type='entity'><p>
  Returns the week number. Language dependent</p></desc>",

    "&_.weeks;":#"<desc type='entity'><p>
  Returns the week number. Zero padded. Language dependent</p></desc>",

    "&_.week.day;":#"<desc type='entity'><p>
  Returns the week day number. 1 for monday if it is ISO
  1 for sunday if it is Gregorian. ISO is default if Gregorian
  is not specified for the <att>calendar</att>.
  Language dependent</p></desc>",

    "&_.week.day.name;":#"<desc type='entity'><p>
  Returns the name of the day. I.e. monday.
  Language dependent</p></desc>",

    "&_.week.day.short-name;":#"<desc type='entity'><p>
  Returns the name of the day. I.e. mo for monday.
  Language dependent</p></desc>",

    "&_.week.name;":#"<desc type='entity'><p>
  the name of the week. I.e. w5 for week number 5 that year.</p></desc>",

    "&_.day;":#"<desc type='entity'><p>Same as <ent>_.month.day</ent>
        </p></desc>",

    "&_.days;":#"<desc type='entity'><p>Same as <ent>_.month.days</ent>
        </p></desc>",

    "&_.ymd;":#"<desc type='entity'><p>
  Returns a date formated like YYYY-MM-DD (ISO date)</p></desc>",

    "&_.ymd_short;":#"<desc type='entity'><p>
  Returns a date formated YYYYMMDD (ISO)</p></desc>",

    "&_.time;":#"<desc type='entity'><p>
  Returns time formated hh:mm:ss (ISO)</p></desc>",

    "&_.timestamp;":#"<desc type='entity'><p>
  Returns a date and time timestamp formated YYYY-MM-DD hh:mm:ss</p></desc>",

    "&_.hour;":#"<desc type='entity'><p>
  Returns the hour. (Time zone dependent data)</p></desc>",

    "&_.hours;":#"<desc type='entity'><p>
  Returns the hour zero padded. (Time zone dependent data)</p></desc>",

    "&_.minute;":#"<desc type='entity'><p>
  Returns minutes, integer value, i.e. 5
  (Time zone dependent data)</p></desc>",

    "&_.minutes;":#"<desc type='entity'><p>
  Returns minutes, zero padded, i.e. 05
  (Time zone dependent data)</p></desc>",

    "&_.second;":#"<desc type='entity'><p>
  Returns seconds. (Time zone dependent data)</p></desc>",

    "&_.seconds;":#"<desc type='entity'><p>
  Returns seconds, zero padded. (Time zone dependent data)</p></desc>",

    "&_.timezone;":#"<desc type='entity'><p>
   Returns the timezone iso name.(Time zone dependent data</p></desc>",

    "&_.timezone.name;":#"<desc type='entity'><p>
  Returns the name of the time zone.</p></desc>",

    "&_.timezone.iso-name;":#"<desc type='entity'><p>
  Returns the ISO name of the timezone</p></desc>",

    "&_.timezone.seconds-to-utc;":#"<desc type='entity'><p>
  The offset to UTC in seconds. (Time zone dependent data)</p></desc>",

    "&_.unix-time;":#"<desc type='entity'><p>
  Returns seconds since 1:st of january 1970 01:00:00</p>
  <p>Time zone dependent data</p></desc>",

    "&_.julian-day;":#"<desc type='entity'><p>
  Returns the Julian day number since the Julian calendar started.</p></desc>",

    "&_.next.something;":#"<desc type='entity'><p>
  Returns date compared to the current date. This will display a
  new date that is next to the current date.</p></desc>",

    "&_.next.second;":#"<desc type='entity'><p>
  Returns the next date the next second.</p></desc>",

    "&_.next.minute;":#"<desc type='entity'><p>
  Returns the next date the next minute.</p></desc>",

    "&_.next.hour;":#"<desc type='entity'><p>
  Returns the next date the next hour.</p></desc>",

    "&_.next.day;":#"<desc type='entity'><p>
  Returns the next date the next day.</p></desc>",

    "&_.next.week;":#"<desc type='entity'><p>
  Returns the next date the next week.</p></desc>",

    "&_.next.month;":#"<desc type='entity'><p>
  Returns the next date the next month.</p></desc>",

    "&_.next.year;":#"<desc type='entity'><p>
  Returns the next date the next year.</p></desc>",

    "&_.prev.something;":#"<desc type='entity'><p>
  Returns date compared to the current date. This will display a
  new date that is previous to the current date.</p></desc>",

    "&_.prev.second;":#"<desc type='entity'><p>
  Returns the previous date the previous second.</p></desc>",

    "&_.prev.minute;":#"<desc type='entity'><p>
  Returns the previous date the previous minute.</p></desc>",

    "&_.prev.hour;":#"<desc type='entity'><p>
  Returns the previous date the previous hour.</p></desc>",

    "&_.prev.day;":#"<desc type='entity'><p>
  Returns the previous date the previous day.</p></desc>",

    "&_.prev.week;":#"<desc type='entity'><p>
  Returns the previous date the previous week.</p></desc>",

    "&_.prev.month;":#"<desc type='entity'><p>
  Returns the previous date the previous month.</p></desc>",

    "&_.prev.year;":#"<desc type='entity'><p>
  Returns the previous date the previous year.</p></desc>",

    "&_.this.something;":#"<desc type='entity'><p>
  </p></desc>",

    "&_.this.second;":#"<desc type='entity'><p>
  Returns the this date this second.</p></desc>",

    "&_.this.minute;":#"<desc type='entity'><p>
  Returns the this date this minute.</p></desc>",

    "&_.this.hour;":#"<desc type='entity'><p>
  Returns the this date this hour.</p></desc>",

    "&_.this.day;":#"<desc type='entity'><p>
  Returns the this date this day.</p></desc>",

    "&_.this.week;":#"<desc type='entity'><p>
  Returns the this date the this week.</p></desc>",

    "&_.this.month;":#"<desc type='entity'><p>
  Returns the this date this month.</p></desc>",

    "&_.this.year;":#"<desc type='entity'><p>
  Returns the this date this year.</p></desc>",

    "&_.default.something;":#"<desc type='entity'><p>
  Returns the this modules settings.</p></desc>",

    "&_.default.calendar;":#"<desc type='entity'><p>
  Returns the this modules default calendar. I.e. \"ISO\", \"Gregorian\" etc.</p></desc>",

    "&_.default.timezone;":#"<desc type='entity'><p>
  Returns the this modules default timezone.</p></desc>",

    "&_.default.timezone.region;":#"<desc type='entity'><p>
  Returns the this modules default timezone region. I.e. Europe if the
  timezone is Europe/Stockholm</p></desc>",

    "&_.default.timezone.detail;":#"<desc type='entity'><p>
  Returns the this modules default timezone specific part. I.e. Stockholm if
  the timezone is Europe/Stockholm</p></desc>",

    "&_.default.language;":#"<desc type='entity'><p>
  Returns the this modules default language.</p></desc>",

  ])
 })
]);
