// $Id: ftp_test.pike,v 1.3 2001/10/09 13:55:12 grubba Exp $
//
// Tests of the ftp protocol module.
//
// Henrik Grubbstr�m 2001-08-24

constant BADARG = 2;
constant NOCONN = 3;
constant TIMEOUT = 4;
constant CONCLOSED = 5;
constant WRITEFAIL = 6;
constant BADCODE = 7;
constant BADDATA = 8;

// Connection setup.

array get_host_port( string url )
{
  string host;
  int port;

  if( sscanf( url, "ftp://%s:%d/", host, port ) != 2 )
    exit( BADARG );
  return ({ host, port });
}

Stdio.File connect( string url )
{
  Stdio.File f = Stdio.File();
  [string host, int port] = get_host_port( url );
  if( !f->connect( (host=="*"?"127.0.0.1":host), port ) )
    exit( NOCONN );

  return f;
}

// Timeout handling

int timestamp;

void touch()
{
  timestamp = time();
}

void timer()
{
  int t = time();

  if (t - timestamp > 30) {
    werror("TIMEOUT!\n");
    werror("Last sent: %O\n", last_sent);
    werror("got_code: %O\n", got_code);
    exit(TIMEOUT);
  }
  call_out(timer, 10);
}

// State machine.

Stdio.File con;

int done;

string inbuf = "";

array(array(string|function(string, string:void))) got_code = ({
  ({ "220", send_user })
});

void got_data(mixed ignored, string data)
{
  inbuf += data;

  array(string) lines = inbuf/"\r\n";

  string code;
  string line_block = "";

  foreach(lines[..sizeof(lines)-2], string line) {
    line_block += line + "\r\n";
    if (!code) {
      code = line[..2];
    }
    if (line[0] != ' ' && line[3] == ' ') {
      array(array(string|function(string, string:void))) cbs =
	got_code + ({ ({ "", bad_code }) });
      got_code = ({});
      foreach(cbs, array(string|function(string,string:void)) cb_info) {
	if (has_prefix(code, cb_info[0])) {
	  cb_info[1](code, line_block);
	  break;
	}
      }
      code = 0;
      line_block = "";
    }
  }
  inbuf = line_block + lines[-1];
}

void con_closed()
{
  exit(!done && CONCLOSED);
}

// Write queue handling.

string sendq = "";
string last_sent = "";

void send(string command)
{
  //werror("FTP: send(%O)\n", command);

  if (!sizeof(sendq)) {
    con->set_write_callback(do_send);
  }
  sendq += command + "\r\n";
}

void do_send(mixed ignored)
{
  int bytes = con->write(sendq, 1);

  if (bytes < 0) {
    exit(WRITEFAIL);
  }
  if (!bytes) {
    exit(CONCLOSED);
  }
  last_sent = sendq[..bytes-1];
  if (bytes == sizeof(sendq)) {
    con->set_write_callback(0);
    sendq = "";
  } else {
    // Partial write.
    sendq = sendq[bytes..];
  }
}

// High-level protocol stuff.

void bad_code(string code, string lines)
{
  werror("Unexpected response code: %O\n", code);
  werror("Last sent:%O\n", last_sent);
  werror("Raw:\n%s\n", lines);
  exit(BADCODE);
}

class do_active_read
{
  object port;
  string command;
  function(string:void) done_cb;
  string buf;
  object fd;

  static void create(string cmd, function(string:void) cb)
  {
    command = cmd;
    done_cb = cb;
    buf = "";
    send_port();
  }

  void send_port()
  {
    port = Stdio.Port(0, got_connect, "127.0.0.1");
    int pno = (int)(port->query_address()/" ")[1];
    send(sprintf("PORT 127,0,0,1,%d,%d", pno>>8, pno & 0xff));
    got_code = ({ ({ "200", send_cmd }) });
  }

  void send_cmd(string code, string lines)
  {
    send(command);
    got_code = ({ ({ "150", got_connection_open }) });
  }

  int con_open;

  void got_connect(mixed ignored)
  {
    fd = port->accept();
    destruct(port);
    port = 0;

    if (con_open) {
      fd->set_nonblocking(got_data, 0, data_closed);
    }
  }

  void got_connection_open(string code, string lines)
  {
    if (fd) {
      fd->set_nonblocking(got_data, 0, data_closed);
    }
    con_open = 1;
    got_code = ({ ({ "226", got_transfer_done }) });
  }

  void got_data(mixed ignored, string str)
  {
    buf += str;
  }

  void data_closed()
  {
    fd->close();
    fd = 0;
    
    if (!con_open) {
      call_out(done_cb, 0, buf);
      buf = "";
      done_cb = 0;
    }
  }

  void got_transfer_done(string code, string lines)
  {
    if (!fd) {
      call_out(done_cb, 0, buf);
      buf = "";
      done_cb = 0;
    }
    con_open = 0;
  }
}

class do_passive_read
{
  inherit do_active_read;

  array(int) port_info;

  static void create(string cmd, function(string:void) cb)
  {
    command = cmd;
    done_cb = cb;
    buf = "";
    send_pasv();
  }

  void send_pasv()
  {
    send("PASV");
    got_code = ({ ({ "227", send_cmd }) });
  }

  void send_cmd(string code, string lines)
  {
    port_info = array_sscanf(lines, "227%*s%d,%d,%d,%d,%d,%d");
    if (sizeof(port_info) != 6) {
      werror("Failed to parse PASV code: %O\n"
	     "Parsed result: { %{%O, %}}\n",
	     lines, port_info);
      exit(BADARG);
    }
    fd = Stdio.File();
    if (!fd->connect(((array(string))port_info[..3])*".",
		     port_info[4]*256+port_info[5])) {
      werror("Failed to connect to passive port: %s\n",
	     ((array(string))port_info)*",");
      exit(NOCONN);
    }
    ::send_cmd(code, lines);
  }
}

// State machine.

void send_user(string code, string lines)
{
  send("USER ftp");
  got_code = ({ ({ "331", send_pass }),
		({ "230", send_help }) });
}

void send_pass(string code, string lines)
{
  send("PASS roxentest@*");
  got_code = ({ ({ "230", send_help }) });
}

void send_help(string code, string lines)
{
  send("HELP");
  got_code = ({ ({ "214", send_feat }) });
}

void send_feat(string code, string lines)
{
  send("FEAT");
  got_code = ({ ({ "211", send_stat }) });
}

void send_stat(string code, string lines)
{
  send("STAT");
  got_code = ({ ({ "211", send_stat_root }) });
}

void send_stat_root(string code, string lines)
{
  send("STAT /");
  got_code = ({ ({ "213", send_mlst_root }) });
}

void send_mlst_root(string code, string lines)
{
  send("MLST /");
  got_code = ({ ({ "250", send_active_list }) });
}

void send_active_list(string code, string lines)
{
  do_active_read("LIST", got_active_list);
}

string active_list;

void got_active_list(string list)
{
  // werror("got_active_list(%O)\n", list);
  active_list = list;
  send_passive_list();
}

void send_passive_list()
{
  do_passive_read("LIST", got_passive_list);
}

void got_passive_list(string list)
{
  if (list != active_list) {
    werror("Active and passive LIST differ:\n"
	   "Active LIST:\n"
	   "%s\n"
	   "Passive LIST:\n"
	   "%s\n",
	   active_list,
	   list);
    exit(BADDATA);
  }
  send_type_i();
}

void send_type_i()
{
  send("TYPE I");
  got_code = ({ ({ "200", send_active_retr_10k }) });
}

void send_active_retr_10k()
{
  do_active_read("RETR 10k.raw", got_active_10k);
}

void got_active_10k(string raw_10k)
{
  if (raw_10k != ("\0"*10240)) {
    werror("Failed to retrieve (active) 10k.\n"
	   "len: %d\n",
	   sizeof(raw_10k));
    exit(BADDATA);
  }
  send_passive_retr_10k();
}

void send_passive_retr_10k()
{
  do_passive_read("RETR 10k.raw", got_passive_10k);
}

void got_passive_10k(string raw_10k)
{
  if (raw_10k != ("\0"*10240)) {
    werror("Failed to retrieve (passive) 10k.\n"
	   "len: %d\n",
	   sizeof(raw_10k));
    exit(BADDATA);
  }
  send_quit("200", "");
}

void send_quit(string code, string lines)
{
  send("QUIT");
  got_code = ({ ({ "221", got_quit }) });
}

void got_quit(string code, string lines)
{
  done = 1;
  got_code = ({});
}

// Initialization.

int main(int argc, array(string) argv)
{
  string url = argv[1];

  con = connect(url);

  con->set_nonblocking(got_data, 0, con_closed);

  call_out(timer, 10);

  touch();

  return -1;
}
