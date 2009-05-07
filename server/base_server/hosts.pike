// This file is part of Roxen WebServer.
// Copyright � 1996 - 2009, Roxen IS.
// $Id: hosts.pike,v 1.37 2009/05/07 14:15:52 mast Exp $

#include <roxen.h>

#ifdef NO_DNS
// Don't do ANY DNS lookups.
string blocking_ip_to_host(string ip) { return ip; }
string blocking_host_to_ip(string host) { return host; }
string quick_ip_to_host(string ip) { return ip; }
string quick_host_to_ip(string host) { return host; }
void ip_to_host(string ipnumber, function callback, mixed ... args)
{
  callback(ipnumber, @args);
}

void host_to_ip(string host, function callback, mixed ... args)
{
  callback(host, @args);
}
#else
public mapping (string:array(mixed)) do_when_found=([]);
Protocols.DNS.async_client dns = Protocols.DNS.async_client();
mapping lookup_funs=([IP_TO_HOST:dns->ip_to_host,HOST_TO_IP:dns->host_to_ip]);

#define lookup(MODE,NAME) lookup_funs[MODE](NAME, got_one_result)
#define LOOKUP(MODE,NAME,CB,ARGS) do{if(!do_when_found[NAME]){do_when_found[NAME]=(CB?({({CB,ARGS})}):({}));lookup(MODE, NAME);} else if(CB) do_when_found[NAME]+=({({CB,ARGS})});}while(0)
#define ISIP(H,CODE) do {mixed entry;if (has_value(H, ":")) {CODE;} else if(sizeof(entry = H / "." ) == 4){int isip = 1;foreach(entry, string s)if((string)((int)s) != s)isip = 0;if(isip) {CODE;};}}while(0)

void got_one_result(string from, string to)
{
#ifdef HOST_NAME_DEBUG
  report_debug("Hostname:  ---- <"+from+"> == <"+to+"> ----\n");
#endif
  if(to) cache_set("hosts", from, to);
  array cbs = do_when_found[ from ];
  m_delete(do_when_found, from);
  foreach(cbs||({}), cbs) cbs[0](to, @cbs[1]);
}

string blocking_ip_to_host(string ip)
{
  if(!stringp(ip))
    return ip;
  ISIP(ip,
       mixed foo;
       if(foo = cache_lookup("hosts", ip)) return foo;
       catch { foo = gethostbyaddr( ip )[0]; };
       foo = foo || ip;
       cache_set("hosts", ip, foo);
       return foo;
       );
  return ip;
}

array gethostbyname(string name) {
  // FIXME: IDN coding should probably be done at a lower level.
  if (String.width (name) > 8 || sscanf (name, "%*[\0-\177]%*c") == 2)
    name = Standards.IDNA.zone_to_ascii (name);
  return dns->gethostbyname(name);
}

string blocking_host_to_ip(string host)
{
  if(!stringp(host) || !strlen(host)) return host;
  if(mixed foo = cache_lookup("hosts", host)) return foo;
  ISIP(host,return host);
  array addr = gethostbyname( host );
  got_one_result(host, addr&&sizeof(addr[1])&&(addr[1][0]));
  m_delete(do_when_found, host);
  return addr&&sizeof(addr[1])?(addr[1][0]):host;
}

string quick_ip_to_host(string ipnumber)
{
#ifdef NO_REVERSE_LOOKUP
  return ipnumber;
#endif
  if(!(int)ipnumber || !strlen(ipnumber)) return ipnumber;
  ipnumber=(ipnumber/" ")[0]; // ?
  if(mixed foo = cache_lookup("hosts", ipnumber)) return foo;
  LOOKUP(IP_TO_HOST,ipnumber,0,0);
  return ipnumber;
}


string quick_host_to_ip(string h)
{
  if(h[-1] == '.') h=h[..strlen(h)-2];
  ISIP(h,return h);
  if(mixed foo = cache_lookup("hosts", h)) return foo;
  LOOKUP(HOST_TO_IP,h,0,0);
  return h;
}

void ip_to_host(string ipnumber, function callback, mixed ... args)
{
#ifdef NO_REVERSE_LOOKUP
  return callback(ipnumber, @args);
#endif
  if(!((int)ipnumber)) return callback(ipnumber, @args);
  if(string entry=cache_lookup("hosts", ipnumber))
  {
    callback(entry, @args);
    return;
  }
  LOOKUP(IP_TO_HOST,ipnumber,callback,args);
}

void host_to_ip(string host, function callback, mixed ... args)
{
  if(!stringp(host) || !strlen(host)) return callback(0, @args);
  if(host[-1] == '.') host=host[..strlen(host)-2];
  ISIP(host,callback(host,@args);return);
  if(string entry=cache_lookup("hosts", host))
  {
    callback(entry, @args);
    return;
  }
  LOOKUP(HOST_TO_IP,host,callback,args);
}

#endif
