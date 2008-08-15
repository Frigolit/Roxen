#charset iso-8859-5
constant required_charset = "iso-8859-5";
/* Bugs by: Per, jhs */
/*
 * name = "Russian language plugin ";
 * doc = "Handles the conversion of numbers and dates to Russian. You have to restart the server for updates to take effect.";
 */

inherit "abstract.pike";

constant cvs_version = "$Id: russian.pike,v 1.10 2008/08/15 12:33:54 mast Exp $";
constant _id = ({ "ru", "russian", ".L������ڎ؎�" });
constant _aliases = ({ "ru", "rus", "russian", "�ҎՎӎӎˎɎ�" });

#define error(x) throw( ({ x, backtrace() }) )

constant months = ({
  "�юΎ׎��Ҏ�", "�ƎŎҎ��̎�", "�͎��Ҏ�", "���ЎҎŎ̎�", "�͎���",
  "�Ɏ��Ύ�", "�Ɏ��̎�", "���׎ǎՎӎԎ�", "�ӎŎΎԎюҎ�", "�ώˎԎю�",
  "�ΎώюҎ�", "�ĎŎˎ��Ҏ�" });

constant days = ({
  "�׎ώӎˎҎŎӎŎΎ؎�","�ЎώΎŎĎŎ̎؎ΎɎ�","�׎ԎώҎΎɎ�","�ӎҎŎĎ�", "�ގŎԎ׎ŎҎ�",
  "�ЎюԎΎɎÎ�", "�ӎՎώԎ�" });

string ordered(int i)
{
  return (string) i + "-��";
}

string date(int timestamp, mapping m)
{
  mapping t1=localtime(timestamp);
  mapping t2=localtime(time(0));

  if(!m) m=([]);

  if(!(m["full"] || m["date"] || m["time"]))
  {
    if(t1["yday"] == t2["yday"] && t1["year"] == t2["year"])
      return "�ӎŎǎώĎΎ�, �� " + ctime(timestamp)[11..15];

    if(t1["yday"] == t2["yday"]-1 && t1["year"] == t2["year"])
      return "�׎ގŎҎ�, v " + ctime(timestamp)[11..15];

    if(t1["yday"] == t2["yday"]+1 && t1["year"] == t2["year"])
      return "�ڎ��׎ԎҎ�, okolo "  + ctime(timestamp)[11..15];

    if(t1["year"] != t2["year"])
      return month(t1["mon"]+1) + " " + (t1["year"]+1900);
    else
      return "" + t1["mday"] + " " + month(t1["mon"]+1);
  }
  if(m["full"])
    return sprintf("%s, %s %s %d",
		   ctime(timestamp)[11..15],
		   ordered(t1["mday"]),
		   month(t1["mon"]+1), t1["year"]+1900);
  if(m["date"])
    return sprintf("%s %s %d", ordered(t1["mday"]),
		   month(t1["mon"]+1), t1["year"]+1900);

  if(m["time"])
    return ctime(timestamp)[11..15];
}

/* Help funtions */
/* gender is "f", "m" or "n" */
string _number_1(int num, string gender)
{
  switch(num)
  {
   case 0:  return "";
   case 1:  return ([ "m" : "�ώĎɎ�",
		      "f" : "�ώĎΎ�",
		      "n" : "�ώĎΎ�" ])[gender];
   case 2:  return ("f" == gender) ? "�Ď�e" : "�Ď׎�";
   case 3:  return "�ԎҎ�";
   case 4:  return "�ގŎԎَҎ�";
   case 5:  return "�ЎюԎ�";
   case 6:  return "�ێŎӎԎ�";
   case 7:  return "�ӎŎ͎�";
   case 8:  return "�׎ώӎŎ͎�";
   case 9:  return "�ĎŎюԎ�";
   default:
     error("russian->_number_1: internal error.\n");
  }
}

string _number_10(int num)
{
  switch(num)
  {
   case 2: return "�Ď׎��ĎÎ��Ԏ�";
   case 3: return "�ԎҎɎĎÎ��Ԏ�";
   case 4: return "�ӎώЎώ�";
   case 5: return "�ЎюԎ؎ĎŎӎю�";
   case 6: return "�ێŎӎԎ؎ĎŎӎю�";
   case 7: return "�ӎŎ͎؎ĎŎӎю�";
   case 8: return "�׎ώӎŎ͎؎ĎŎӎю�";
   case 9: return "�ĎŎ׎юΎώӎԎ�";
   default:
     error("russian->_number_10: internal error.\n");
  }
}

string _number_100(int num)
{
  switch(num)
  {
   case 1: return "�ӎԎ�";
   case 2: return "�Ď׎ŎӎԎ�";
   case 3: case 4:
     return _number_1(num, "m")+"�ӎԎ�";
   case 5: case 6: case 7: case 8: case 9:
     return _number_1(num, "m")+"�ӎώ�";
   default:
     error("russian->_number_10: internal error.\n");
  }
}

string _number(int num, string gender);

string _number_1000(int num)
{
  if (num == 1)
    return "�Ԏَӎюގ�";

  string pre = _number(num, "f");
  switch(num % 10)
  {
   case 1: return pre + " �Ԏَӎюގ�";
   case 2: case 3: case 4:
     return pre + " �Ԏَӎюގ�";
   default:
     return pre + " �Ԏَӎю�";
  }
}

string _number_1000000(int num)
{
  if (num == 1)
    return "�͎Ɏ̎̎Ɏώ�";

  string pre = _number(num, "m");
  switch(num % 10)
  {
   case 1: return pre + " �͎Ɏ̎̎Ɏώ�";
   case 2: case 3: case 4:
     return pre + " �͎Ɏ̎̎ɎώΎ�";
   default:
     return pre + " �͎Ɏ̎̎ɎώΎώ�";
  }
}

string _number(int num, string gender)
{
  if (!gender)   /* Solitary numbers are inflected as masculine */
    gender = "m";
  if (!num)
    return "";

  if (num < 10)
    return _number_1(num, gender);

  if (num < 20)
    return ([ 10: "�ĎŎӎюԎ�",
	      11: "�ώĎɎΎΎ��ĎÎ��Ԏ�",
	      12: "�Ď׎ŎΎ��ĎÎ��Ԏ�",
	      13: "�ԎҎɎΎ��ĎÎ��Ԏ�",
	      14: "�ގŎԎَҎΎ��ĎÎ��Ԏ�",
	      15: "�ЎюԎΎ��ĎÎ��Ԏ�",
	      16: "�ێŎӎԎΎ��ĎÎ��Ԏ�",
	      17: "�ӎŎ͎Ύ��ĎÎ��Ԏ�",
	      18: "�׎ώӎŎ͎Ύ��ĎÎ��Ԏ�",
	      19: "�ĎŎ׎юԎΎ��ĎÎ��Ԏ�" ])[num];
  if (num < 100)
    return _number_10(num/10) + " " + _number_1(num%10, gender);

  if (num < 1000)
    return _number_100(num/100) + " " + _number(num%100, gender);

  if (num < 1000000)
    return _number_1000(num/1000) + " " + _number(num%1000, gender);

  return _number_1000000(num/1000000) + " " + _number(num%1000000, gender);
}


string number(int num, string|void gender)
{
  if (!gender)   /* Solitary numbers are inflected as masculine */
    gender = "m";
  if (num<0) {
    return("�͎ɎΎՎ�"+_number(-num, gender));
  } if (num) {
    return(_number(num, gender));
  } else {
    return("�Ύώ̎�");
  }
}


protected void create()
{
  roxen.dump( __FILE__ );
}
