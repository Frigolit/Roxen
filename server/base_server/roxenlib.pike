#include <roxen.h>
inherit "http";

// $Id: roxenlib.pike,v 1.121 1999/10/21 17:09:59 mast Exp $
// This code has to work both in the roxen object, and in modules.
#if !efun(roxen)
#define roxen roxenp()
#endif

#include <stat.h>

#define ipaddr(x,y) (((x)/" ")[y])
#define old_rxml_compat 1

string gif_size(object gif)
{
  array xy=Dims.dims()->get(gif);
  return "width="+xy[0]+" height="+xy[1];
}

static string extract_query(string from)
{
  if(!from) return "";
  if(sscanf(from, "%*s?%s%*[ \t\n]", from))
    return (from/"\r")[0];
  return "";
}

static mapping build_env_vars(string f, object id, string path_info)
{
  string addr=id->remoteaddr || "Internal";
  mixed tmp;
  mapping new = ([]);
  object tmpid;
  
  if(id->query && strlen(id->query))
    new->INDEX=id->query;
    
  if(path_info && strlen(path_info))
  {
    string t, t2;
    if(path_info[0] != '/')
      path_info = "/" + path_info;
    
    t = t2 = "";
    
    // Kludge
    if (id->misc->path_info == path_info) {
      // Already extracted
      new["SCRIPT_NAME"]=id->not_query;
    } else {
      new["SCRIPT_NAME"]=
	id->not_query[0..strlen(id->not_query)-strlen(path_info)-1];
    }
    new["PATH_INFO"]=path_info;


    while(1)
    {
      // Fix PATH_TRANSLATED correctly.
      t2 = id->conf->real_file(path_info, id);
      if(t2)
      {
	new["PATH_TRANSLATED"] = t2 + t;
	break;
      }
      tmp = path_info/"/" - ({""});
      if(!sizeof(tmp))
	break;
      path_info = "/" + (tmp[0..sizeof(tmp)-2]) * "/";
      t = tmp[-1] +"/" + t;
    }
  } else
    new["SCRIPT_NAME"]=id->not_query;
  tmpid = id;
  while(tmpid->misc->orig)
    // internal get
    tmpid = tmpid->misc->orig;

  // Begin "SSI" vars.
  if(sizeof(tmp = tmpid->not_query/"/" - ({""})))
    new["DOCUMENT_NAME"]=tmp[-1];
  
  new["DOCUMENT_URI"]= tmpid->not_query;
  
  if((tmp = file_stat(tmpid->conf->real_file(tmpid->not_query||"", tmpid)))
     && sizeof(tmp))
    new["LAST_MODIFIED"]=http_date(tmp[3]);

  // End SSI vars.


  if(tmp = id->conf->real_file(new["SCRIPT_NAME"], id))
    new["SCRIPT_FILENAME"] = tmp;
    
  if(tmp = id->conf->real_file("/", id))
    new["DOCUMENT_ROOT"] = tmp;

  if(!new["PATH_TRANSLATED"])
    m_delete(new, "PATH_TRANSLATED");
  else if(new["PATH_INFO"][-1] != '/' && new["PATH_TRANSLATED"][-1] == '/')
    new["PATH_TRANSLATED"] = 
      new["PATH_TRANSLATED"][0..strlen(new["PATH_TRANSLATED"])-2];

  // HTTP_ style variables:

  mapping hdrs;

  if ((hdrs = id->request_headers)) {
    foreach(indices(hdrs) - ({ "authorization", "proxy-authorization",
			       "security-scheme", }), string h) {
      string hh = "HTTP_" + replace(upper_case(h),
				    ({ " ", "-", "\0", "=" }),
				    ({ "_", "_", "", "_" }));

      new[hh] = replace(hdrs[h], ({ "\0" }), ({ "" }));
    }
    if (!new["HTTP_HOST"]) {
      if(objectp(id->my_fd) && id->my_fd->query_address(1))
	new["HTTP_HOST"] = replace(id->my_fd->query_address(1)," ",":");
    }
  } else {
    if(id->misc->host)
      new["HTTP_HOST"]=id->misc->host;
    else if(objectp(id->my_fd) && id->my_fd->query_address(1))
      new["HTTP_HOST"]=replace(id->my_fd->query_address(1)," ",":");
    if(id->misc["proxy-connection"])
      new["HTTP_PROXY_CONNECTION"]=id->misc["proxy-connection"];
    if(id->misc->accept) {
      if (arrayp(id->misc->accept)) {
	new["HTTP_ACCEPT"]=id->misc->accept*", ";
      } else {
	new["HTTP_ACCEPT"]=(string)id->misc->accept;
      }
    }

    if(id->misc->cookies)
      new["HTTP_COOKIE"] = id->misc->cookies;
  
    if(sizeof(id->pragma))
      new["HTTP_PRAGMA"]=indices(id->pragma)*", ";

    if(stringp(id->misc->connection))
      new["HTTP_CONNECTION"]=id->misc->connection;
    
    new["HTTP_USER_AGENT"] = id->client*" "; 
    
    if(id->referer && sizeof(id->referer))
      new["HTTP_REFERER"] = id->referer*""; 
  }

  new["REMOTE_ADDR"]=addr;
    
  if(roxen->quick_ip_to_host(addr) != addr)
    new["REMOTE_HOST"]=roxen->quick_ip_to_host(addr);

  catch {
    if(id->my_fd) {
      new["REMOTE_PORT"] = ipaddr(id->my_fd->query_address(), 1);
    }
  };
    
  if (id->query && sizeof(id->query)) {
    new["QUERY_STRING"] = id->query;
  }

  if(id->realauth)
    new["REMOTE_USER"] = (id->realauth / ":")[0];
    
  if(id->data && strlen(id->data))
  {
    if(id->misc["content-type"])
      new["CONTENT_TYPE"]=id->misc["content-type"];
    else
      new["CONTENT_TYPE"]="application/x-www-form-urlencoded";
    new["CONTENT_LENGTH"]=(string)strlen(id->data);
  }
    
  if(id->query && strlen(id->query))
    new["INDEX"]=id->query;
    
  new["REQUEST_METHOD"]=id->method||"GET";
  new["SERVER_PORT"] = id->my_fd?
    ((id->my_fd->query_address(1)||"foo unknown")/" ")[1]: "Internal";
    
  return new;
}

static mapping build_roxen_env_vars(object id)
{
  mapping new = ([]);
  mixed tmp;

  if(id->cookies->RoxenUserID)
    new["ROXEN_USER_ID"]=id->cookies->RoxenUserID;

  new["COOKIES"] = "";
  foreach(indices(id->cookies), tmp)
    {
      new["COOKIE_"+tmp] = id->cookies[tmp];
      new["COOKIES"]+= tmp+" ";
    }
	
  foreach(indices(id->config), tmp)
    {
      new["WANTS_"+replace(tmp, " ", "_")]="true";
      if(new["CONFIGS"])
	new["CONFIGS"] += " " + replace(tmp, " ", "_");
      else
	new["CONFIGS"] = replace(tmp, " ", "_");
    }

  foreach(indices(id->variables), tmp)
  {
    string name = replace(tmp," ","_");
    if (id->variables[tmp] && (sizeof(id->variables[tmp]) < 8192)) {
      /* Some shells/OS's don't like LARGE environment variables */
      new["QUERY_"+name] = replace(id->variables[tmp],"\000"," ");
      new["VAR_"+name] = replace(id->variables[tmp],"\000","#");
    }
    if(new["VARIABLES"])
      new["VARIABLES"]+= " " + name;
    else
      new["VARIABLES"]= name;
  }
      
  foreach(indices(id->prestate), tmp)
  {
    new["PRESTATE_"+replace(tmp, " ", "_")]="true";
    if(new["PRESTATES"])
      new["PRESTATES"] += " " + replace(tmp, " ", "_");
    else
      new["PRESTATES"] = replace(tmp, " ", "_");
  }
	
  foreach(indices(id->supports), tmp)
  {
    new["SUPPORTS_"+replace(tmp-",", " ", "_")]="true";
    if (new["SUPPORTS"])
      new["SUPPORTS"] += " " + replace(tmp, " ", "_");
    else
      new["SUPPORTS"] = replace(tmp, " ", "_");
  }
  return new;
}


static string decode_mode(int m)
{
  string s;
  s="";
  
  if(S_ISLNK(m))  s += "Symbolic link";
  else if(S_ISREG(m))  s += "File";
  else if(S_ISDIR(m))  s += "Dir";
  else if(S_ISCHR(m))  s += "Special";
  else if(S_ISBLK(m))  s += "Device";
  else if(S_ISFIFO(m)) s += "FIFO";
  else if(S_ISSOCK(m)) s += "Socket";
  else if((m&0xf000)==0xd000) s+="Door";
  else s+= "Unknown";
  
  s+=", ";
  
  if(S_ISREG(m) || S_ISDIR(m))
  {
    s+="<tt>";
    if(m&S_IRUSR) s+="r"; else s+="-";
    if(m&S_IWUSR) s+="w"; else s+="-";
    if(m&S_IXUSR) s+="x"; else s+="-";
    
    if(m&S_IRGRP) s+="r"; else s+="-";
    if(m&S_IWGRP) s+="w"; else s+="-";
    if(m&S_IXGRP) s+="x"; else s+="-";
    
    if(m&S_IROTH) s+="r"; else s+="-";
    if(m&S_IWOTH) s+="w"; else s+="-";
    if(m&S_IXOTH) s+="x"; else s+="-";
    s+="</tt>";
  } else {
    s+="--";
  }
  return s;
}

constant MONTHS=(["Jan":0, "Feb":1, "Mar":2, "Apr":3, "May":4, "Jun":5,
	         "Jul":6, "Aug":7, "Sep":8, "Oct":9, "Nov":10, "Dec":11,
		 "jan":0, "feb":1, "mar":2, "apr":3, "may":4, "jun":5,
	         "jul":6, "aug":7, "sep":8, "oct":9, "nov":10, "dec":11,]);

static int _match(string w, array (string) a)
{
  string q;
  if(!stringp(w)) // Internal request..
    return -1;
  foreach(a, q) 
    if(stringp(q) && strlen(q) && glob(q, w)) 
      return 1; 
}

static int is_modified(string a, int t, void|int len)
{
  mapping t1;
  int day, year, month, hour, minute, second, length;
  string m, extra;
  if(!a)
    return 1;
  t1=gmtime(t);
   // Expects 't' as returned from time(), not UTC.
  sscanf(lower_case(a), "%*s, %s; %s", a, extra);
  if(extra && sscanf(extra, "length=%d", length) && len && length != len)
    return 0;

  if(search(a, "-") != -1)
  {
    sscanf(a, "%d-%s-%d %d:%d:%d", day, m, year, hour, minute, second);
    year += 1900;
    month=MONTHS[m];
  } else   if(search(a, ",") == 3) {
    sscanf(a, "%*s, %d %s %d %d:%d:%d", day, m, year, hour, minute, second);
    if(year < 1900) year += 1900;
    month=MONTHS[m];
  } else if(!(int)a) {
    sscanf(a, "%*[^ ] %s %d %d:%d:%d %d", m, day, hour, minute, second, year);
    month=MONTHS[m];
  } else {
    sscanf(a, "%d %s %d %d:%d:%d", day, m, year, hour, minute, second);
    month=MONTHS[m];
    if(year < 1900) year += 1900;
  }

  if(year < (t1["year"]+1900))                                
    return 0;
  else if(year == (t1["year"]+1900)) 
    if(month < (t1["mon"]))  
      return 0;
    else if(month == (t1["mon"]))      
      if(day < (t1["mday"]))   
	return 0;
      else if(day == (t1["mday"]))	     
	if(hour < (t1["hour"]))  
	  return 0;
	else if(hour == (t1["hour"]))      
	  if(minute < (t1["min"])) 
	    return 0;
	  else if(minute == (t1["min"]))     
	    if(second < (t1["sec"])) 
	      return 0;
  return 1;
}

string short_name(string long_name)
{
  long_name = replace(long_name, " ", "_");
  return lower_case(long_name);
}

string strip_config(string from)
{
  sscanf(from, "/<%*s>%s", from);
  return from;
}

string strip_prestate(string from)
{
  sscanf(from, "/(%*s)%s", from);
  return from;
}

#define _error defines[" _error"]
#define _extra_heads defines[" _extra_heads"]
#define _rettext defines[" _rettext"]

static string parse_rxml(string what, object id,
			 void|object file, 
			 void|mapping defines)
{
  if(!objectp(id)) error("No id passed to parse_rxml\n");
  return id->conf->parse_rxml( what, id, file, defines );
}

constant iso88591
=([ "&nbsp;":   "�",
    "&iexcl;":  "�",
    "&cent;":   "�",
    "&pound;":  "�",
    "&curren;": "�",
    "&yen;":    "�",
    "&brvbar;": "�",
    "&sect;":   "�",
    "&uml;":    "�",
    "&copy;":   "�",
    "&ordf;":   "�",
    "&laquo;":  "�",
    "&not;":    "�",
    "&shy;":    "�",
    "&reg;":    "�",
    "&macr;":   "�",
    "&deg;":    "�",
    "&plusmn;": "�",
    "&sup2;":   "�",
    "&sup3;":   "�",
    "&acute;":  "�",
    "&micro;":  "�",
    "&para;":   "�",
    "&middot;": "�",
    "&cedil;":  "�",
    "&sup1;":   "�",
    "&ordm;":   "�",
    "&raquo;":  "�",
    "&frac14;": "�",
    "&frac12;": "�",
    "&frac34;": "�",
    "&iquest;": "�",
    "&Agrave;": "�",
    "&Aacute;": "�",
    "&Acirc;":  "�",
    "&Atilde;": "�",
    "&Auml;":   "�",
    "&Aring;":  "�",
    "&AElig;":  "�",
    "&Ccedil;": "�",
    "&Egrave;": "�",
    "&Eacute;": "�",
    "&Ecirc;":  "�",
    "&Euml;":   "�",
    "&Igrave;": "�",
    "&Iacute;": "�",
    "&Icirc;":  "�",
    "&Iuml;":   "�",
    "&ETH;":    "�",
    "&Ntilde;": "�",
    "&Ograve;": "�",
    "&Oacute;": "�",
    "&Ocirc;":  "�",
    "&Otilde;": "�",
    "&Ouml;":   "�",
    "&times;":  "�",
    "&Oslash;": "�",
    "&Ugrave;": "�",
    "&Uacute;": "�",
    "&Ucirc;":  "�",
    "&Uuml;":   "�",
    "&Yacute;": "�",
    "&THORN;":  "�",
    "&szlig;":  "�",
    "&agrave;": "�",
    "&aacute;": "�",
    "&acirc;":  "�",
    "&atilde;": "�",
    "&auml;":   "�",
    "&aring;":  "�",
    "&aelig;":  "�",
    "&ccedil;": "�",
    "&egrave;": "�",
    "&eacute;": "�",
    "&ecirc;":  "�",
    "&euml;":   "�",
    "&igrave;": "�",
    "&iacute;": "�",
    "&icirc;":  "�",
    "&iuml;":   "�",
    "&eth;":    "�",
    "&ntilde;": "�",
    "&ograve;": "�",
    "&oacute;": "�",
    "&ocirc;":  "�",
    "&otilde;": "�",
    "&ouml;":   "�",
    "&divide;": "�",
    "&oslash;": "�",
    "&ugrave;": "�",
    "&uacute;": "�",
    "&ucirc;":  "�",
    "&uuml;":   "�",
    "&yacute;": "�",
    "&thorn;":  "�",
    "&yuml;":   "�",
]);

constant replace_entities=indices( iso88591 )+({"&lt;","&gt;","&amp;","&#022;","&#34;","&#39;","&#0;"});
constant replace_values  =values( iso88591 )+ ({"<",">","&","\"","\"","\'","\000"});

constant safe_characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"/"";
constant empty_strings = ({""})*sizeof(safe_characters);

static int is_safe_string(string in)
{
  return strlen(in) && !strlen(replace(in, safe_characters, empty_strings));
}

static string make_tag_attributes(mapping in)
{
  array a=(array(string))indices(in), b=(array(string))values(in);
  int sl=-1;
  sort(a,b);
  for(int i=0; i<sizeof(a); i++)
    if(a[i]=="/" && b[i]=="/")
      sl=i;
    else
      a[i]+="=\""+html_encode_string( b[i] )+"\"";
  if(sl>=0 && sl<sizeof(a)-1) {
    a[sl]=a[sizeof(a)-1];
    a[sizeof(a)-1]="/";
  }
  return a*" ";
}

static string make_tag(string s,mapping in)
{
  string q = make_tag_attributes(in);
  return "<"+s+(strlen(q)?" "+q:"")+">";
}

static string make_empty_elem_tag(string s,mapping in)
{
  // Creates an XML empty-element tag
  string q = make_tag_attributes(in);
  if(in["/"]!="/")
    q=(strlen(q)?q+" /":"/");
  return "<"+s+" "+q+">";
}

static string make_container(string s,mapping in, string contents)
{
  return make_tag(s,in)+contents+"</"+s+">";
}

static string dirname( string file )
{
  if(!file) 
    return "/";
  mixed tmp;
  if(file[-1] == '/')
    if(strlen(file) > 1)
      return file[0..strlen(file)-2];
    else
      return file;
  tmp=file/"/";
  if(sizeof(tmp)==2 && tmp[0]=="")
    return "/";
  return tmp[0..sizeof(tmp)-2]*"/";
}

static string conv_hex( int color )
{
  int c;
  string result;

  result = "";
  for (c=0; c < 6; c++, color>>=4)
    switch (color & 15)
    {
     case 0: case 1: case 2: case 3: case 4:
     case 5: case 6: case 7: case 8: case 9:
      result = (color & 15) + result;
      break;
     case 10: 
      result = "A" + result;
      break;
     case 11: 
      result = "B" + result;
      break;
     case 12: 
      result = "C" + result;
      break;
     case 13: 
      result = "D" + result;
      break;
     case 14: 
      result = "E" + result;
      break;
     case 15: 
      result = "F" + result;
      break;
    }
  return "#" + result;
  
}

static string add_config( string url, array config, multiset prestate )
{
  if(!sizeof(config)) 
    return url;
  if(strlen(url)>5 && (url[1] == "(" || url[1] == "<"))
    return url;
  return "/<" + config * "," + ">" + add_pre_state(url, prestate);
}

string msectos(int t)
{
  if(t<1000) /* One sec. */
  {
    return sprintf("0.%02d sec", t/10);
  } else if(t<6000) {  /* One minute */
    return sprintf("%d.%02d sec", t/1000, (t%1000 + 5) / 10);
  } else if(t<3600000) { /* One hour */
    return sprintf("%d:%02d m:s", t/60000,  (t%60000)/1000);
  } 
  return sprintf("%d:%02d h:m", t/3600000, (t%3600000)/60000);
}
static object extension_regexp = Regexp(".*\\.([^#~]*)");             
int|string extension( string f, object|void id) 
{
  string ext, key;
  if(!f || !strlen(f)) return "";
  if(!id || !(ext = id->misc[key="_ext_"+f])) {
    array split = extension_regexp->split(f);                           
    if(!split||!sizeof(split)) 
      ext="";
    else {
      ext = lower_case(split[0]);
      if(ext == "bak" || ext == "old")
	if(f[-1] == "~" || f[-1] == "#")
	  ext = extension(f[..strlen(f)-5]);
	else 
	  ext = extension(f[..strlen(f)-4]);
    }
    if(id)
      id->misc[key]=ext;
  }
  return ext;
}

static int backup_extension( string f )
{
  if(!strlen(f)) 
    return 1;
  return (f[-1] == '#' || f[-1] == '~' 
	  || (f[-1] == 'd' && sscanf(f, "%*s.old")) 
	  || (f[-1] == 'k' && sscanf(f, "%*s.bak")));
}

/* ================================================= */
/* Arguments: Anything Returns: Memory usage of the argument.  */
int get_size(mixed x)
{
  if(mappingp(x))
    return 8 + 8 + get_size(indices(x)) + get_size(values(x));
  else if(stringp(x))
    return strlen(x)+8;
  else if(arrayp(x))
  {
    mixed f;
    int i;
    foreach(x, f)
      i += get_size(f);
    return 8 + i;    // (refcount + pointer) + arraysize..
  } else if(multisetp(x)) {
    mixed f;
    int i;
    foreach(indices(x), f)
      i += get_size(f);
    return 8 + i;    // (refcount + pointer) + arraysize..
  } else if(objectp(x) || functionp(x)) {
    return 8 + 16; // (refcount + pointer) + object struct.
    // Should consider size of global variables / refcount 
  }
  return 20; // Ints and floats are 8 bytes, refcount and float/int.
}


static int ipow(int what, int how)
{
  return (int)pow(what, how);
}

/* This one will remove .././ etc. in the path. Might be useful :) */
/* ================================================= */

static string simplify_path(string file)
{
  string tmp;
  int t2,t1;

  // Faster for most cases since "./" and "../" rarely exists.
  if(!strlen(file) || ((search(file, "./") == -1) && (file[-1] != '.')))
    return file;

  if(file[0] != '/')
    t2 = 1;
	
  if(strlen(file) > 1
     && file[-2]=='/'
     && ((file[-1] == '/') || (file[-1]=='.'))
	)
    t1=1;

  tmp=combine_path("/", file);

  if(t1) tmp += "/.";
  if(t2) return tmp[1..];
    
  return tmp;
}

/* Returns a short date string from a time-int 
   ===========================================
   Arguments: int (time)
   Returns:   string ("short_date")
   */

static string short_date(int timestamp)
{
  int date = time(1);
  
  if(ctime(date)[20..23] != ctime(timestamp)[20..23])
    return ctime(timestamp)[4..9] +" "+ ctime(timestamp)[20..23];
  
  return ctime(timestamp)[4..9] +" "+ ctime(timestamp)[11..15];
}


int httpdate_to_time(string date)
{     
   if (intp(date)) return -1;
   // Tue, 28 Apr 1998 13:31:29 GMT
   // 0    1  2    3    4  5  6
   int mday,hour,min,sec,year;
   string month;
   if(sscanf(date,"%*s, %d %s %d %d:%d:%d GMT",mday,month,year,hour,min,sec)==6)
     return mktime((["year":year-1900,
		     "mon":MONTHS[lower_case(month)],
		     "mday":mday,
		     "hour":hour,
		     "min":min,
		     "sec":sec,
		     "timezone":0]));
   
   
   return -1; 
}

static string int2roman(int m)
{
  string res="";
  if (m>10000000||m<0) return "que";
  while (m>999) { res+="M"; m-=1000; }
  if (m>899) { res+="CM"; m-=900; }
  else if (m>499) { res+="D"; m-=500; }
  else if (m>399) { res+="CD"; m-=400; }
  while (m>99) { res+="C"; m-=100; }
  if (m>89) { res+="XC"; m-=90; }
  else if (m>49) { res+="L"; m-=50; }
  else if (m>39) { res+="XL"; m-=40; }
  while (m>9) { res+="X"; m-=10; }
  if (m>8) return res+"IX";
  else if (m>4) { res+="V"; m-=5; }
  else if (m>3) return res+"IV";
  while (m) { res+="I"; m--; }
  return res;
}

static string number2string(int n,mapping m,mixed names)
{
  string s;
  switch (m->type)
  {
   case "string":
    if (functionp(names)) 
    { s=names(n); break; }
    if (!arrayp(names)||n<0||n>=sizeof(names)) s="";
    else s=names[n];
    break;
   case "roman":
    s=int2roman(n);
    break;
   default:
    return (string)n;
  }

  switch(m["case"]) {
    case "lower": return lower_case(s);
    case "upper": return upper_case(s);
    case "capitalize": return capitalize(s);
  }

#if old_rxml_compat
  if (m->lower) return lower_case(s);
  if (m->upper) return upper_case(s);
  if (m->cap||m->capitalize) return capitalize(s);
#endif

  return s;
}


static string image_from_type( string t )
{
  if(t)
  {
    sscanf(t, "%s/%*s", t);
    switch(t)
    {
     case "audio":
     case "sound":
      return "internal-gopher-sound";
     case "image":
      return "internal-gopher-image";
     case "application":
      return "internal-gopher-binary";
     case "text":
      return "internal-gopher-text";
    }
  }
  return "internal-gopher-unknown";
}

#define  PREFIX ({ "bytes", "kB", "MB", "GB", "TB", "HB" })
static string sizetostring( int size )
{
  float s = (float)size;
  if(size<0) 
    return "--------";
  size=0;

  while( s > 1024.0 )
  {
    s /= 1024.0;
    size ++;
  }
  return sprintf("%.1f %s", s, PREFIX[ size ]);
}

mapping proxy_auth_needed(object id)
{
  mixed res = id->conf->check_security(proxy_auth_needed, id);
  if(res)
  {
    if(res==1) // Nope...
      return http_low_answer(403, "You are not allowed to access this proxy");
    if(!mappingp(res))
      return 0; // Error, really.
    res->error = 407;
    return res;
  }
  return 0;
}

string program_filename()
{
  return roxen->filename(this_object()) ||
    search(master()->programs, object_program(this_object()));
}

string program_directory()
{
  array(string) p = program_filename()/"/";
  return (sizeof(p)>1? p[..sizeof(p)-2]*"/" : getcwd());
}

string html_encode_string(string str)
// Encodes str for use as a literal in html text.
{
  return replace(str, ({"&", "<", ">", "\"", "\'", "\000" }),
		 ({"&amp;", "&lt;", "&gt;", "&#34;", "&#39;", "&#0;"}));
}

string html_decode_string(string str)
// Decodes str, opposite to html_encode_string()
{
  return replace(str, replace_entities, replace_values);
}

string html_encode_tag_value(string str)
// Encodes str for use as a value in an html tag.
{
  return "\"" + replace(str, ({"&", "\""}), ({"&amp;", "&quot;"})) + "\"";
}

string strftime(string fmt, int t)
{
  mapping lt = localtime(t);
  array a = fmt/"%";
  int i;
  for (i=1; i < sizeof(a); i++) {
    if (!sizeof(a[i])) {
      a[i] = "%";
      i++;
      continue;
    }
    string res = "";
    switch(a[i][0]) {
    case 'a':	// Abbreviated weekday name
      res = ({ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" })[lt->wday];
      break;
    case 'A':	// Weekday name
      res = ({ "Sunday", "Monday", "Tuesday", "Wednesday",
	       "Thursday", "Friday", "Saturday" })[lt->wday];
      break;
    case 'b':	// Abbreviated month name
    case 'h':	// Abbreviated month name
      res = ({ "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" })[lt->mon];
      break;
    case 'B':	// Month name
      res = ({ "January", "February", "March", "April", "May", "June",
	       "July", "August", "September", "October", "November", "December" })[lt->mon];
      break;
    case 'c':	// Date and time
      res = strftime(sprintf("%%a %%b %02d  %02d:%02d:%02d %04d",
			     lt->mday, lt->hour, lt->min, lt->sec, 1900 + lt->year), t);
      break;
    case 'C':	// Century number; 0-prefix
      res = sprintf("%02d", 19 + lt->year/100);
      break;
    case 'd':	// Day of month [1,31]; 0-prefix
      res = sprintf("%02d", lt->mday);
      break;
    case 'D':	// Date as %m/%d/%y
      res = strftime("%m/%d/%y", t);
      break;
    case 'e':	// Day of month [1,31]; space-prefix
      res = sprintf("%2d", lt->mday);
      break;
    case 'H':	// Hour (24-hour clock) [0,23]; 0-prefix
      res = sprintf("%02d", lt->hour);
      break;
    case 'I':	// Hour (12-hour clock) [1,12]; 0-prefix
      res = sprintf("%02d", 1 + (lt->hour + 11)%12);
      break;
    case 'j':	// Day number of year [1,366]; 0-prefix
      res = sprintf("%03d", lt->yday);
      break;
    case 'k':	// Hour (24-hour clock) [0,23]; space-prefix
      res = sprintf("%2d", lt->hour);
      break;
    case 'l':	// Hour (12-hour clock) [1,12]; space-prefix
      res = sprintf("%2d", 1 + (lt->hour + 11)%12);
      break;
    case 'm':	// Month number [1,12]; 0-prefix
      res = sprintf("%02d", lt->mon + 1);
      break;
    case 'M':	// Minute [00,59]
      res = sprintf("%02d", lt->min);
      break;
    case 'n':	// Newline
      res = "\n";
      break;
    case 'p':	// a.m. or p.m.
      if (lt->hour < 12) {
	res = "a.m.";
      } else {
	res = "p.m.";
      }
      break;
    case 'r':	// Time in 12-hour clock format with %p
      res = strftime("%l:%M %p", t);
      break;
    case 'R':	// Time as %H:%M
      res = sprintf("%02d:%02d", lt->hour, lt->min);
      break;
    case 'S':	// Seconds [00,61]
      res = sprintf("%02", lt->sec);
      break;
    case 't':	// Tab
      res = "\t";
      break;
    case 'T':	// Time as %H:%M:%S
      res = sprintf("%02d:%02d:%02d", lt->hour, lt->min, lt->sec);
      break;
    case 'u':	// Weekday as a decimal number [1,7], Sunday == 1
      res = sprintf("%d", lt->wday + 1);
      break;
    case 'w':	// Weekday as a decimal number [0,6], Sunday == 0
      res = sprintf("%d", lt->wday);
      break;
    case 'x':	// Date
      res = strftime("%a %b %d %Y", t);
      break;
    case 'X':	// Time
      res = sprintf("%02d:%02d:%02d", lt->hour, lt->min, lt->sec);
      break;
    case 'y':	// Year [00,99]
      // FIXME: Does this handle negative years.
      res = sprintf("%02d", lt->year % 100);
      break;
    case 'Y':	// Year [0000.9999]
      res = sprintf("%04d", 1900 + lt->year);
      break;

    case 'U':	/* FIXME: Week number of year as a decimal number [00,53],
		 * with Sunday as the first day of week 1
		 */
      break;
    case 'V':	/* Week number of the year as a decimal number [01,53],
		 * with  Monday  as  the first day of the week.  If the
		 * week containing 1 January has four or more  days  in
		 * the  new  year, then it is considered week 1; other-
		 * wise, it is week 53 of the previous  year,  and  the
		 * next week is week 1
		 */
      break;
    case 'W':	/* FIXME: Week number of year as a decimal number [00,53],
		 * with Monday as the first day of week 1
		 */
      break;
    case 'Z':	/* FIXME: Time zone name or abbreviation, or no bytes if
		 * no time zone information exists
		 */
      break;
    default:
      // FIXME: Some kind of error indication?
      break;
    }
    a[i] = res + a[i][1..];
  }
  return(a*"");
}

object get_module (string modname)
// Resolves a string as returned by get_modname to a module object if
// one exists.
{
  string cname, mname;
  int mid = 0;

  if (sscanf (modname, "%s/%s", cname, mname) != 2 ||
      !sizeof (cname) || !sizeof(mname)) return 0;
  sscanf (mname, "%s#%d", mname, mid);

  foreach (roxen->configurations, object conf) {
    mapping moddata;
    if (conf->name == cname && (moddata = conf->modules[mname])) {
      if (mid >= 0) {
	if (moddata->copies) return moddata->copies[mid];
      }
      else if (moddata->enabled) return moddata->enabled;
      if (moddata->master) return moddata->master;
      return 0;
    }
  }

  return 0;
}

string get_modname (object module)
// Returns a string uniquely identifying the given module on the form
// `<config name>/<module short name>#<copy>', where `<copy>' is 0 for
// modules with no copies.
{
  if (!module) return 0;

  foreach (roxen->configurations, object conf) {
    string mname = conf->otomod[module];
    if(mname)
      return conf->name + "/" + mname;
  }

  return 0;
}

// This determines the full module name in approximately the same way
// as the config UI.
string get_modfullname (object module)
{
  if (module) {
    string name = 0;
    if (module->query_name) name = module->query_name();
    if (!name || !sizeof (name)) name = module->register_module()[1];
    return name;
  }
  else return 0;
}

// method for use by tags that replace variables in their content,
// like formoutput, sqloutput and others. Note that this function
// always does the appropriate rxml parsing; the output from it should
// not be parsed again.
string do_output_tag( mapping args, array (mapping) var_arr, string contents,
		      object id )
{
  string quote = args->quote || "#";
  mapping other_vars = id->misc->variables;
  string new_contents = "", unparsed_contents = "";
  int first;

  // multi_separator must default to \000 since one sometimes need to
  // pass multivalues through several output tags, and it's a bit
  // tricky to set it to \000 in a tag..
  string multi_separator = args->multi_separator || args->multisep || "\000";

  if (args->preprocess)
    contents = parse_rxml( contents, id );

  switch (args["debug-input"]) {
    case 0: break;
    case "log":
      report_debug ("tag input: " + contents + "\n");
      break;
    case "comment":
      new_contents = "<!--\n" + html_encode_string (contents) + "\n-->";
      break;
    default:
      new_contents = "\n<br><b>[</b><pre>" +
	html_encode_string (contents) + "</pre><b>]</b>\n";
  }

  if (args->sort)
  {
    array order;

    order = args->sort / "," - ({ "" });
    var_arr = Array.sort_array( var_arr,
				lambda (mapping m1, mapping m2, array order)
				{
				  int tmp;
				     
				  foreach (order, string field)
				  if (field[0] == '-')
				    if (!catch (tmp = (m1[field[1..]]
						       < m2[field[1..]])) &&
					tmp)
				      return tmp;
				    else
				      ;
				  else if (field[0] == '+')
				    if (!catch (tmp = (m1[field[1..]]
						       > m2[field[1..]])) &&
					tmp)
				      return tmp;
				    else
				      ;
				  else
				    if (!catch (tmp = (m1[field]
						       > m2[field])) &&
					tmp)
				      return tmp;
				  return 0;
				}, order );
  }

  if (args->range)
  {
    int begin, end;
    string b, e;
    

    sscanf( args->range, "%s..%s", b, e );
    if (!b || b == "")
      begin = 0;
    else
      begin = (int )b;
    if (!e || e == "")
      end = -1;
    else
      end = (int )e;

    if (begin < 0)
      begin += sizeof( var_arr );
    if (end < 0)
      end += sizeof( var_arr );
    if (begin > end)
      return "";
    if (begin < 0)
      if (end < 0)
	return "";
      else
	begin = 0;
    var_arr = var_arr[begin..end];
  }

  first = 1;
  foreach (var_arr, mapping vars)
  {
    if (args->set)
      foreach (indices (vars), string var) {
	mixed val = vars[var];
	if (!val) val = args->zero || "";
	else {
	  if (arrayp( val ))
	    val = Array.map (val, lambda (mixed v) {return (string) v;}) *
	      multi_separator;
	  else
	    val = replace ((string) val, "\000", multi_separator);
	  if (!sizeof (val)) val = args->empty || "";
	}
	id->variables[var] = val;
      }

    id->misc->variables = vars;

    if (!args->replace || lower_case( args->replace ) != "no")
    {
      array exploded = contents / quote;
      if (!(sizeof (exploded) & 1))
	return "<b>Content ends inside a replace field</b>";

      for (int c=1; c < sizeof( exploded ); c+=2)
	if (exploded[c] == "")
	  exploded[c] = quote;
	else
	{
	  array(string) options =  exploded[c] / ":";
	  string var = trim (options[0]);
	  mixed val = vars[var];
	  array(string) encodings = ({});
	  string multisep = multi_separator;
	  string zero = args->zero || "";
	  string empty = args->empty || "";

	  foreach(options[1..], string option) {
	    array (string) foo = option / "=";
	    string optval = trim (foo[1..] * "=");

	    switch (lower_case (trim( foo[0] ))) {
	      case "empty":
		empty = optval;
		break;
	      case "zero":
		zero = optval;
		break;
	      case "multisep":
	      case "multi_separator":
		multisep = optval;
		break;
	      case "quote":	// For backward compatibility.
		optval = lower_case (optval);
		switch (optval) {
		  case "mysql": case "sql": case "oracle":
		    encodings += ({optval + "-dtag"});
		    break;
		  default:
		    encodings += ({optval});
		}
		break;
	      case "encode":
		encodings += Array.map (lower_case (optval) / ",", trim);
		break;
	      default:
		return "<b>Unknown option " + trim (foo[0]) +
		  " in replace field " + ((c >> 1) + 1) + "</b>";
	    }
	  }

	  if (!val)
	    if (zero_type (vars[var]) && (args->debug || id->misc->debug))
	      val = "<b>No variable " + options[0] + "</b>";
	    else
	      val = zero;
	  else {
	    if (arrayp( val ))
	      val = Array.map (val, lambda (mixed v) {return (string) v;}) *
		multisep;
	    else
	      val = replace ((string) val, "\000", multisep);
	    if (!sizeof (val)) val = empty;
	  }

	  if (!sizeof (encodings))
	    encodings = args->encode ?
	      Array.map (lower_case (args->encode) / ",", trim) : ({"html"});
	  foreach (encodings, string encoding)
	    switch (encoding) {
	      case "none":
	      case "":
		break;

	      case "http":
		// HTTP encoding.
		val = http_encode_string (val);
		break;

	      case "cookie":
		// HTTP cookie encoding.
		val = http_encode_cookie (val);
		break;

	      case "url":
		// HTTP encoding, including special characters in URL:s.
		val = http_encode_url (val);
		break;

	      case "html":
		// For generic html text and in tag arguments. Does
		// not work in RXML tags (use dtag or stag instead).
		val = html_encode_string (val);
		break;

	      case "dtag":
		// Quote quotes for a double quoted tag argument. Only
		// for internal use, i.e. in arguments to other RXML tags.
		val = replace (val, "\"", "\"'\"'\"");
		break;

	      case "stag":
		// Quote quotes for a single quoted tag argument. Only
		// for internal use, i.e. in arguments to other RXML tags.
		val = replace(val, "'", "'\"'\"'");
		break;

	      case "pike":
		// Pike string quoting (e.g. for use in a <pike> tag).
		val = replace (val,
			       ({ "\"", "\\", "\n" }),
			       ({ "\\\"", "\\\\", "\\n" }));
		break;

	      case "js":
	      case "javascript":
		// Javascript string quoting.
		val = replace (val,
			       ({ "\b", "\014", "\n", "\r", "\t", "\\", "'", "\"" }),
			       ({ "\\b", "\\f", "\\n", "\\r", "\\t", "\\\\",
				  "\\'", "\\\"" }));
		break;

	      case "mysql":
		// MySQL quoting.
		val = replace (val,
			       ({ "\"", "'", "\\" }),
			       ({ "\\\"" , "\\'", "\\\\" }) );
		break;

	      case "sql":
	      case "oracle":
		// SQL/Oracle quoting.
		val = replace (val, "'", "''");
		break;

	      case "mysql-dtag":
		// MySQL quoting followed by dtag quoting.
		val = replace (val,
			       ({ "\"", "'", "\\" }),
			       ({ "\\\"'\"'\"", "\\'", "\\\\" }));
		break;

	      case "mysql-pike":
		// MySQL quoting followed by Pike string quoting.
		val = replace (val,
			       ({ "\"", "'", "\\", "\n" }),
			       ({ "\\\\\\\"", "\\\\'",
				  "\\\\\\\\", "\\n" }) );
		break;

	      case "sql-dtag":
	      case "oracle-dtag":
		// SQL/Oracle quoting followed by dtag quoting.
		val = replace (val,
			       ({ "'", "\"" }),
			       ({ "''", "\"'\"'\"" }) );
		break;

	      default:
		return "<b>Unknown encoding " + encoding +
		  " in replace field " + ((c >> 1) + 1) + "</b>";
	    }

	  exploded[c] = val;
	}

      if (first)
	first = 0;
      else if (args->delimiter)
	new_contents += args->delimiter;
      new_contents += args->preprocess ? exploded * "" :
	parse_rxml (exploded * "", id);
      if (args["debug-output"]) unparsed_contents += exploded * "";
    }
    else {
      new_contents += args->preprocess ? contents : parse_rxml (contents, id);
      if (args["debug-output"]) unparsed_contents += contents;
    }
  }

  switch (args["debug-output"]) {
    case 0: break;
    case "log":
      report_debug ("tag output: " + unparsed_contents + "\n");
      break;
    case "comment":
      new_contents += "<!--\n" + html_encode_string (unparsed_contents) + "\n-->";
      break;
    default:
      new_contents = "\n<br><b>[</b><pre>" + html_encode_string (unparsed_contents) +
	"</pre><b>]</b>\n";
  }

  id->misc->variables = other_vars;
  return new_contents;
}

string fix_relative( string file, object id )
{
  string path = id->not_query;
  // +(id->misc->path_info?id->misc->path_info:"");
//   werror(" Fix relative, path = "+path+"; file = "+file+"; " );
  if(file != "" && file[0] == '/') 
    ;
  else if(file != "" && file[0] == '#') 
    file = path + file;
  else
    file = dirname(path) + "/" +  file;
//   werror(" res = "+simplify_path(file)+"\n");
  return simplify_path(file);
}

Stdio.File open_log_file( string logfile )
{
  mapping m = localtime(time());
  m->year += 1900;	/* Adjust for years being counted since 1900 */
  m->mon++;		/* Adjust for months being counted 0-11 */
  if(m->mon < 10) m->mon = "0"+m->mon;
  if(m->mday < 10) m->mday = "0"+m->mday;
  if(m->hour < 10) m->hour = "0"+m->hour;
  logfile = replace(logfile,({"%d","%m","%y","%h" }),
                    ({ (string)m->mday, (string)(m->mon),
                       (string)(m->year),(string)m->hour,}));
  if(strlen(logfile))
  {
    object lf=Stdio.File( logfile, "wac");
    if(!lf) 
    {
      mkdirhier(logfile);
      if(!(lf=Stdio.File( logfile, "wac")))
      {
        report_error("Failed to open logfile. ("+logfile+"): "
                     + strerror( errno() )+"\n");
        return 0;
      }
    }
    return lf;
  }
  return Stdio.stderr;
}

string trim( string what )
{
  if (stringp (what)) {
    sscanf(reverse(what), "%*[ \t]%s", what);
    sscanf(reverse(what), "%*[ \t]%s", what);
  }
  return what;
}

string|int tagtime(int t, mapping m, object id, object language)
{
  string s;
  mixed eris;
  string res;

  if (m->adjust) t+=(int)m->adjust;

  if (m["int"]) return (string)t;

  if (m->part)
  {
    string sp;
    if(m->type == "ordered")
    {
      m->type="string";
      sp = "ordered";
    }

    switch (m->part)
    {
     case "year":
      return number2string(localtime(t)->year+1900,m,
			   language(m->lang, sp||"number"));
     case "month":
      return number2string(localtime(t)->mon+1,m,
			   language(m->lang, sp||"month"));
     case "week":
      return number2string(Calendar.datetime(t)->week,m,
                           language(m->lang, sp||"number"));
     case "day":
     case "wday":
      return number2string(localtime(t)->wday+1,m,
			   language(m->lang, sp||"day"));
     case "date":
     case "mday":
      return number2string(localtime(t)->mday,m,
			   language(m->lang, sp||"number"));
     case "hour":
      return number2string(localtime(t)->hour,m,
			   language(m->lang, sp||"number"));

     case "beat":
       //FIXME This should be done inside Calendar.
       mapping lt=Calendar.datetime(t);
       int secs=3600;
       secs+=lt->timezone;
       secs-=lt->DST*3600;
       secs+=lt->hour*3600;
       secs+=lt->minute*60;
       secs+=lt->second;
       secs%=24*3600;
       float beats=secs/86.4;
       if(!sp) return sprintf("@%03d",(int)beats);
       return number2string((int)beats,m,
                            language(m->lang, sp||"number"));
     case "min":  // Not part of RXML 1.4
     case "minute":
      return number2string(localtime(t)->min,m,
			   language(m->lang, sp||"number"));
     case "sec":  // Not part of RXML 1.4
     case "second":
      return number2string(localtime(t)->sec,m,
			   language(m->lang, sp||"number"));
     case "yday":
      return number2string(localtime(t)->yday,m,
			   language(m->lang, sp||"number"));
     default: return "";
    }
  }
  else if(m->type) {
    switch(m->type)
    {
     case "iso":
      eris=localtime(t);
      return sprintf("%d-%02d-%02d", (eris->year+1900),
		     eris->mon+1, eris->mday);

     case "discordian":
#if efun(discdate)
      eris=discdate(t);
      res=eris[0];
      if(m->year)
	res += " in the YOLD of "+eris[1];
      if(m->holiday && eris[2])
	res += ". Celebrate "+eris[2];
      return res;
#else
      return "Discordian date support disabled";
#endif
     case "stardate":
#if efun(stardate)
      return (string)stardate(t, (int)m->prec||1);
#else
      return "Stardate support disabled";
#endif
    }
  }
  s=language(m->lang, "date")(t,m);

  if(m["case"])
    switch(lower_case(m["case"])) {
    case "upper": return upper_case(s);
    case "lower": return lower_case(s);
    case "capitalize": return capitalize(s);
    }

#if old_rxml_compat
  // Not part of RXML 1.4
  if (m->upper) {
    s=upper_case(s);
    report_warning("Old RXML in "+(id->query||id->not_query)+
      ", contains upper attribute in a tag. Use case=\"upper\" instead.");
  }
  if (m->lower) {
    s=lower_case(s);
    report_warning("Old RXML in "+(id->query||id->not_query)+
      ", contains lower attribute in a tag. Use case=\"lower\" instead.");
  }
  if (m->cap||m->capitalize) {
    s=capitalize(s);
    report_warning("Old RXML in "+(id->query||id->not_query)+
      ", contains capitalize or cap attribute in a tag. Use case=\"capitalize\" instead.");
  }
  return s;
#endif
}

string|int API_read_file(object id, string file)
{
  string s, f = fix_relative(file, id);
  id = id->clone_me();
 
  if(id->scan_for_query)
    f = id->scan_for_query( f );
  s = id->conf->try_get_file(f, id);

  if (!s) {

    // Might be a PATH_INFO type URL.
    array a = id->conf->open_file( f, "r", id );
    if(a && a[0])
    {
      s = a[0]->read();
      if(a[1]->raw)
      {
        s -= "\r";
        if(!sscanf(s, "%*s\n\n%s", s))
          sscanf(s, "%*s\n%s", s);
      }
    }
    if(!s)
      return 0;
  }

  return s;
}

int time_dequantifier(mapping m)
{
  float t = 0.0;
  if (m->seconds) t+=((float)(m->seconds));
  if (m->minutes) t+=((float)(m->minutes))*60;
  if (m->beats)   t+=((float)(m->beats))*86.4;
  if (m->hours)   t+=((float)(m->hours))*3600;
  if (m->days)    t+=((float)(m->days))*86400;
  if (m->weeks)   t+=((float)(m->weeks))*604800;
  if (m->months)  t+=((float)(m->months))*(24*3600*30.436849);
  if (m->years)   t+=((float)(m->years))*(3600*24*365.242190);
  return (int)t;
}
