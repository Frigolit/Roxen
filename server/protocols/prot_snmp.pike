// This is a roxen protocol module.
// Copyright � 2001 - 2007, Roxen IS.

/*
 * $Id: prot_snmp.pike,v 2.7 2008/02/19 14:58:18 marty Exp $
 *
 * SNMP protocol support.
 *
 * Based on the Roxen SNMP agent by Honza Petrous <hop@unibase.cz>.
 *
 * 2007-08-29 Henrik Grubbstr�m
 */

inherit Protocol;
constant supports_ipless = 1;
constant name = "snmp";
constant prot_name = "snmp";
constant default_port = 161;

#ifdef SNMP_DEBUG
#define DWRITE(X...)		werror("DEBUG: " + X)
#define SNMPAGENT_MSG(X...)	werror("SNMPAGENT: " + X)
#else /* !SNMP_DEBUG */
#define DWRITE(X...)
#define SNMPAGENT_MSG(X...)
#endif /* SNMP_DEBUG */

#define LOC_M(X, Y)	(Y)

/*
 * References:
 *
 * RFC 1213        base MIB
 *                 system.* (all done)
 *                 snmp.* (all done, but most of them all still death)
 * RFC 1215        Convention for defining traps
 * RFC 1227        SNMP MUX procotol and MIB
 * RFC 2248        Network Services Monitoring MIB
 * RFC 2576        Coexistence between v1, v2 and v3 of SNMP protocol
 * RFC 2594        Definitions of managed objects for WWW services
 *
 * TODO:
 *   * Traps.
 *   * Module reloading.
 *   * SNMP v3
 *   * Security.
 */

class SNMP_Port {
  inherit Protocols.SNMP.protocol;

  static int udp_errno = 0;

  int errno()
  {
    return udp_errno;
  }

  int bind(int|void port, function got_connection, string|void ip)
  {
    // NOTE: We know stuff about how Protocols.SNP.protocol is implemented!
    udp_errno = 0;
    catch {
      if (::bind(port, ip)) {
	DWRITE("protocol.bind: success!\n");

	DWRITE("protocol.create: local adress:port bound: [%s:%d].\n",
	       ip||"ANY", port);

	if (got_connection) set_nonblocking(got_connection);

	return 1;
      }
    }; 
    //# error ...
    udp_errno = errno();
    DWRITE("protocol.create: can't bind to the socket.\n");
  }

  static void create() {}
}

SNMP_Port port_obj;

ADT.Trie mib = ADT.Trie();

//! cf RFC 1213.
class SystemMIB
{
  inherit SNMP.SimpleMIB;

  static void create()
  {
    ::create(SNMP.INTERNET_OID + ({ 2, 1, 1 }), ({}),
	     ({
	       UNDEFINED,
	       // system.sysDescr
	       SNMP.String("Roxen Webserver SNMP agent v" +
			   ("$Revision: 2.7 $"/" ")[1],
			   "sysDescr"),
	       // system.sysObjectID
	       SNMP.OID(SNMP.RIS_OID_WEBSERVER,
			"sysObjectID"),
	       // system.sysUpTime
	       SNMP.Tick(lambda() {
			   return (time(1) - roxen->start_time)*100;
			 }, "sysUpTime"),
	       // system.sysContact
	       SNMP.String(lambda() {
			     return query("snmp_syscontact");
			   }, "sysContact"),
	       // system.sysName
	       SNMP.String(lambda() {
			     return query("snmp_sysname");
			   }, "sysName"),
	       // system.sysLocation
	       SNMP.String(lambda() {
			     return query("snmp_syslocation");
			   }, "sysLocation"),
	       // system.sysServices
	       SNMP.Integer(lambda() {
			      return query("snmp_sysservices");
			    }, "sysServices"),
	     }));
  }
}

// Statistics.
static SNMP.Counter snmpinpkts = SNMP.Counter(0, "snmpInPkts");
static SNMP.Counter snmpoutpkts = SNMP.Counter(0, "snmpOutPkts");
static SNMP.Counter snmpbadver = SNMP.Counter(0, "snmpBadVers");
static SNMP.Counter snmpbadcommnames = SNMP.Counter(0,
						    "snmpInBadCommunityNames");
static SNMP.Counter snmpbadcommuses = SNMP.Counter(0,
						   "snmpInBadCommunityUses");
static SNMP.Counter snmpenaauth = SNMP.Integer(0, "snmpEnableAuthenTraps");

//! cf RFC 1213.
class SNMPMIB
{
  inherit SNMP.SimpleMIB;

  static void create()
  {
    ::create(SNMP.INTERNET_OID + ({ 2, 1, 11 }), ({}),
	     ({
	       UNDEFINED,
	       // snmp.snmpInPkts
	       snmpinpkts,
	       // snmp.snmpOutPkts
	       snmpoutpkts,
	       // snmp.snmpBadVers
	       snmpbadver,
	       // snmp.snmpInBadCommunityNames
	       snmpbadcommnames,
	       // snmp.snmpInBadCommunityUses
	       snmpbadcommuses,
	       // snmp.snmpInASNParseErrs
	       SNMP.NULL_COUNTER,
	       // 7 is not used
	       UNDEFINED,
	       // snmp.snmpInTooBigs
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInNoSuchNames
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInBadValues
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInReadOnlys
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInGenErrs
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInTotalReqVars
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInTotalSetVars
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInGetRequests
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInGetNexts
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInSetRequests
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInGetResponses
	       SNMP.NULL_COUNTER,
	       // snmp.snmpInTraps
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutTooBigs
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutNoSuchNames
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutBadValues
	       SNMP.NULL_COUNTER,
	       // 23 is not used
	       UNDEFINED,
	       // snmp.snmpOutGenErrs
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutGetRequests
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutGetNexts
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutSetRequests
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutGetResponses
	       SNMP.NULL_COUNTER,
	       // snmp.snmpOutTraps
	       SNMP.NULL_COUNTER,
	       // snmp.snmpEnableAuthenTraps
	       snmpenaauth,
	     }));
  }
}

class RoxenGlobalMIB
{
  inherit SNMP.SimpleMIB;

  // Global information.

  static void create()
  {
    ::create(SNMP.RIS_OID_WEBSERVER + ({ 1 }), ({}),
	     ({
	       UNDEFINED,
	       UNDEFINED,	/* restart */
	       SNMP.Integer(lambda() {
			      return sizeof(roxen->configurations);
			    }, "vsCount"),
	       UNDEFINED,	/* Reserved for DBManager (see below). */
	       SNMP.Gauge(lambda() {
			    return sizeof(Stdio.get_all_active_fd());
			  }, "activeFDCount"),
	     }));
  }
}

class DBManagerMIB
{
  inherit SNMP.SimpleMIB;

  // DBManager information.

  int db_status(string pattern)
  {
    Sql.Sql sql = connect_to_my_mysql(0, "mysql");
    if (!sql) return 0;
    array(mapping(string:string)) res =
      sql->query("SHOW STATUS LIKE %s", pattern);
    if (!res || !sizeof(res)) return 0;
    return (int)(res[0]->Value || res[0]->value);
  }

  static void create()
  {
    ::create(SNMP.RIS_OID_WEBSERVER + ({ 1, 3 }), ({}),
	     ({
	       UNDEFINED,
	       SNMP.String(lambda() {
			     Sql.Sql sql = connect_to_my_mysql(0, "mysql");
			     if (!sql) return "";
			     return sql->master_sql->server_info() || "";
			   }, "serverVersion"),
	       SNMP.String(lambda() {
			     Sql.Sql sql = connect_to_my_mysql(0, "mysql");
			     if (!sql) return "";
			     return sql->master_sql->host_info() || "";
			   }, "connectionType"),
	       SNMP.Integer(lambda() {
			      Sql.Sql sql = connect_to_my_mysql(0, "mysql");
			      return sql && sql->master_sql->protocol_info();
			    }, "protocolVersion"),
	       SNMP.Tick(lambda() {
			   return db_status("Uptime")*100;
			 }, "uptime"),
	       SNMP.Gauge(lambda() {
			    return db_status("Threads_connected");
			  }, "numThreads"),
	       SNMP.Gauge(lambda() {
			    return db_status("Threads_running");
			  }, "numActiveThreads"),
	       SNMP.Counter(lambda() {
			      return db_status("Questions");
			    }, "numQueries"),
	       SNMP.Counter(lambda() {
			      return db_status("Slow_queries");
			    }, "numSlowQueries"),
	     }));
  }
}

static void setup_mib()
{
  mib->merge(SystemMIB());
  mib->merge(SNMPMIB());
  mib->merge(RoxenGlobalMIB());
  mib->merge(DBManagerMIB());
}

#define SNMP_OP_GETREQUEST	0
#define SNMP_OP_GETNEXT		1
#define SNMP_OP_GETRESPONSE	2
#define SNMP_OP_SETREQUEST	3
#define SNMP_OP_TRAP		4

#define LOG_EVENT(txt, pkt) log_event(txt, pkt)

static mapping events = ([]);
static void log_event(string txt, mapping pkt) {
  SNMPAGENT_MSG(sprintf("event: %O: %O\n", txt, pkt));
  if(zero_type(events[txt]))
    events[txt] += ([ pkt->ip : ([ pkt->community: 1]) ]) ;
  else if(zero_type(events[txt][pkt->ip]))
    events[txt][pkt->ip] += ([ pkt->community: 1]);
  else
    events[txt][pkt->ip][pkt->community]++;
}

//! Binding of an OID to a value.
//!
//! FIXME: Ought to be an ASN1 object.
class Binding
{
  array(int) oid;
  Standards.ASN1.Types.Object value;

  static void create(array(int)|Standards.ASN1.Types.Object duo,
		     Standards.ASN1.Types.Object|void val)
  {
    if (val) {
      oid = duo;
      value = val;
    } else {
      oid = duo->elements[0]->id;
      value = duo->elements[1]->value;
    }
  }
}

//! decode ASN1 data, if garbaged or unsupported ignore it
static mapping(string:int|string|array) decode_asn1_msg(mapping rawd)
{
  object(Standards.ASN1.Types.Object) xdec =
    port_obj->snmp_der_decode(rawd->data);
  DWRITE("xdec: %O\n", xdec);
  int version = xdec->elements[0]->value;
  DWRITE("Version: %O\n", version);

  if (version < 2) {
    // 0: SNMPv1	RFC 1157
    // 1: SNMPv2c	RCC 1901, RFC 1905
    object(Standards.ASN1.Types.Object) pdu = xdec->elements[2];
    int errno = pdu->elements[1]->value;
    return ([
      "msgid": pdu->elements[0]->value,
      "ip":rawd->ip,
      "port":rawd->port,
      "error-status":errno,
      "error-string":port_obj->snmp_errlist[errno],
      "error-index":pdu->elements[2]->value,
      "version":version,
      "community":xdec->elements[1]->value,
      "op":pdu->get_tag(),
      "bindings":map(pdu->elements[3]->elements, Binding),
    ]);
	      
  } else {
    // 3: SNMPv3	RFC 2262, RFC 2272, RFC 2572, RFC 3412

    // FIXME: Not supported yet!
    snmpbadver->value++;
    return 0;
  }
}

#define SNMP_SUCCESS		0
#define SNMP_SEND_ERROR		1

int writemsg(string rem_addr, int rem_port, int version,
	     Standards.ASN1.Types.Object pdu)
{
  //: send SNMP encoded message and return status
  //: OK, in most cases :)

  object msg;
  string rawd;
  int msize;

  msg = Standards.ASN1.Types.asn1_sequence(({
	   Standards.ASN1.Types.asn1_integer(version),
           Standards.ASN1.Types.asn1_octet_string(port_obj->snmp_community),
	   pdu}));

  DWRITE("protocol.writemsg: %O\n", msg);

  rawd = msg->get_der();

  DWRITE("protocol.writemsg: %O:%O <== %O\n", rem_addr, rem_port, rawd);

  msize = port_obj->send(rem_addr, rem_port, rawd);
  return (msize = sizeof(rawd) ? SNMP_SUCCESS : SNMP_SEND_ERROR);
}



//!
//! Encode and send a PDU response.
//!
//! @param bindings
//!   An array of bindings to return.
//! @param origdata
//!   Original received decoded pdu that this response corresponds to
//! @param errcode
//!   Error code
//! @param erridx
//!   Error index
//! @returns
//!   Request ID
int send_response(array(Binding) bindings,
		  mapping origdata, int|void errcode, int|void erridx)
{
  //: GetResponse-PDU low call
  object pdu;
  int id = origdata->msgid;
  int flg;
  array vararr = ({});

  foreach(bindings, Binding binding) {
    vararr += ({
      Standards.ASN1.Types.asn1_sequence(
		   ({ SNMP.OID(binding->oid),
		      binding->value,
		   })
		   )
    });
  }

  pdu = Protocols.LDAP.ldap_privates.asn1_context_sequence(2,
	       ({Standards.ASN1.Types.asn1_integer(id), // request-id
		 Standards.ASN1.Types.asn1_integer(errcode), // error-status
		 Standards.ASN1.Types.asn1_integer(erridx), // error-index
		 Standards.ASN1.Types.asn1_sequence(vararr)})
	       );

  // now we have PDU ...
  flg = writemsg(origdata->ip, origdata->port, origdata->version, pdu);

  return id;
}

static void got_connection(mapping data)
{
  mapping pdata;
  array rdata = ({});
  int msgid, op, errnum = 0, setflg = 0;
  string attrname = "0", comm;

  SNMPAGENT_MSG("Got UDP data: %O\n", data);

  snmpinpkts->value++;
  pdata = decode_asn1_msg(data);

  //SNMPAGENT_MSG(sprintf("Got parsed: %O", pdata));

  if(!mappingp(pdata)) {
    SNMPAGENT_MSG("SNMP message can not be decoded. Silently ommited.");
    return;
  }

  foreach(urls;;mapping(string:mixed) mu) {
    DWRITE("mu: %O\n", mu);
    Configuration c = mu->conf;
    if (!c->inited) {
      c->enable_all_modules();
    }
    ADT.Trie submib;
    if (submib = c->mib) {
      if (c->mib_version >= mu->mib_version) {
	mu->mib_version = c->mib_version;
	mib->merge(submib);
      }
    }
  }

  msgid = pdata->msgid;
  comm = pdata->community || "";
  op = pdata->op;

#if 0
  // test for correct community string
  if(!chk_access("ro", pdata)) {
    snmpbadcommnames->value++;
    errnum = 5 /*SNMP_ERR_GENERR*/;
    attrname = indices(pdata->bindings[0])[0];
    LOG_EVENT("Bad community name", pdata);
    authfailure_trap(pdata);
    return;
  }
#endif /* 0 */

  foreach(pdata->bindings; int index; Binding binding) {
    array(int) oid = binding->oid;
    switch(op) {
    case SNMP_OP_GETNEXT:
      DWRITE("Get next for %O...\n", oid);
      oid = mib->next(oid);
      if (!oid) break;
      // FALL_THROUGH
    case SNMP_OP_GETREQUEST:
      mixed val = mib->lookup(oid);
      DWRITE("Lookup (%O) ==> %O\n", oid, val);
      if (zero_type(val)) {
	array(int) next_oid = mib->next(oid);
	if (next_oid && (sizeof(next_oid) > sizeof(oid))) {
	  for (int i = 0; i < sizeof(oid); i++) {
	    if (oid[i] != next_oid[i]) {
	      next_oid = 0;
	      break;
	    }
	  }
	  if (next_oid) {
	    // RFC 1905 4.2.1.3:
	    //   Otherwise, the variable binding's value field is set to
	    //   `noSuchInstance'.
	    val = SNMP.NO_SUCH_INSTANCE;
	  }
	}
	// RFC 1905 4.2.1.2:
	//   Otherwise, if the variable binding's name does not have an OBJECT
	//   IDENTIFIER prefix which exactly matches the OBJECT IDENTIFIER
	//   prefix of any (potential) variable accessible by this request,
	//   then its value field is set to `noSuchObject'.
	val = val || SNMP.NO_SUCH_OBJECT;
      }
      if (objectp(val) && val->update_value) {
	// Update value callback.
	val->update_value();
      }
      if (intp(val)) val = SNMP.Integer(val);
      else if (stringp(val)) val = SNMP.String(val);
      if (objectp(val)) {
	rdata += ({ Binding(oid, val) });
      }
      break;

    case SNMP_OP_SETREQUEST:
#if 0
      mixed attrval = binding->value;
      val = mib->set(attrname, attrval, pdata[msgid]);
      if(arrayp(val) && sizeof(val))
	setflg = val[0];
	//rdata[attrname] += ({ "int", attrval });
      rdata += ({ Binding(({1,3,6,1,2,1,1,3,0}),
			  SNMP.Tick(get_uptime())) });
      if (arrayp(val) && stringp(val[1]))
	report_warning(val[1]);
#endif /* 0 */
      break;
    }
  }

  if(op == SNMP_OP_SETREQUEST && !setflg && !errnum) {
    LOG_EVENT("Set not allowed", pdata);
    snmpbadcommuses->value++;
  }

  //SNMPAGENT_MSG(sprintf("Answer: %O", rdata));
  snmpoutpkts->value++;
  if(!sizeof(rdata)) {
    if (!errnum) LOG_EVENT("No such name", pdata);
    if (sizeof(pdata->bindings)) {
      rdata = ({ Binding(pdata->bindings[0]->oid,
			 SNMP.OID(pdata->bindings[0]->oid)) });
    }
    send_response(rdata, pdata, errnum || 2 /*SNMP_NOSUCHNAME*/);
    // future note: v2c, v3 protos want to return "endOfMibView"
  } else {
    send_response(rdata, pdata);
  }
}

// NOTE: Code duplication from Protocol!
static void bind(void|int ignore_eaddrinuse)
{
  if (bound) return;
  if (!port_obj) port_obj = SNMP_Port();
  Privs privs = Privs (sprintf ("Binding %s", get_url()));
  if (port_obj->bind(port, got_connection, ip))
  {
    privs = 0;
    bound = 1;
    setup_mib();
    return;
  }
  privs = 0;
#if constant(System.EAFNOSUPPORT)
  if (port_obj->errno() == System.EAFNOSUPPORT) {
    // Fail permanently.
    error("Invalid address " + ip);
  }
#endif /* System.EAFNOSUPPORT */
#if constant(System.EADDRINUSE) || constant(system.EADDRINUSE)
  if (
#if constant(System.EADDRINUSE)
      (port_obj->errno() == System.EADDRINUSE)
#else /* !constant(System.EADDRINUSE) */
      (port_obj->errno() == system.EADDRINUSE)
#endif /* constant(System.EADDRINUSE) */
      ) {
    if (!ignore_eaddrinuse && (retries++ < 10)) {
      // We may get spurious failures on rebinding ports on some OS'es
      // (eg Linux, WIN32). See [bug 3031].
      report_error(LOC_M(6, "Failed to bind %s (%s)")+"\n",
		   get_url(), strerror(port_obj->errno()));
      report_notice(LOC_M(62, "Attempt %d. Retrying in 1 minute.")+"\n",
		    retries);
      call_out(bind, 60);
    }
  }
  else
#endif /* constant(System.EADDRINUSE) || constant(system.EADDRINUSE) */
  {
    report_error(LOC_M(6, "Failed to bind %s (%s)")+"\n",
		 get_url(), strerror(port_obj->errno()));
#if 0
    werror (describe_backtrace (backtrace()));
#endif
  }
}

static void create( mixed ... args )
{
#if constant(roxen.set_up_snmp_variables)
  roxen.set_up_snmp_variables( this_object() );
#else

#define TYPE_STRING            1
#define TYPE_FILE              2
#define TYPE_INT               3
#define TYPE_DIR               4
#define TYPE_STRING_LIST       5

  defvar("snmp_community", ({"public:ro"}), "Community string",
         TYPE_STRING_LIST,
         "One community name per line. Default permissions are 'read-only'. "
	 "'Read-write' permissions can be specified by appending :rw to the "
	 "community name (for example mypub:rw).");
/*
  defvar("snmp_mode", "smart", "Agent mode",
         TYPE_STRING_LIST,
         "Standard SNMP server mode, muxed SNMP mode, "
         "proxy, agentx or automatic (smart) mode.",
         ({"smart", "agent", "agentx", "smux", "proxy" }));
*/
  defvar("snmp_global_traphosts", ({}),"Trap destinations",
         TYPE_STRING_LIST,
         "The SNMP traphost URL for sending common traps (like coldstart).");

  defvar("snmp_syscontact","","System MIB: Contact",
         TYPE_STRING,
         "The textual identification of the contact person for this managed "
         "node, together with information on how to contact this person.");
  defvar("snmp_sysname","","System MIB: Name",
         TYPE_STRING,
         "An administratively-assigned name for this managed node. By "
         "convention, this is the node's fully-qualified domain name.");
  defvar("snmp_syslocation","","System MIB: Location",
         TYPE_STRING,
         "The physical location of this node (e.g., `telephone closet, 3rd "
         "floor').");
  defvar("snmp_sysservices",72,"System MIB: Services",
         TYPE_INT,
         "A value which indicates the set of services that this entity "
         "primarily offers.");
#endif
  ::create( @args );
}