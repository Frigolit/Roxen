#charset iso-8859-5
/* Bugs by: Per */
/*
 * name = "Russian language plugin ";
 * doc = "Handles the conversion of numbers and dates to Russian. You have to restart the server for updates to take effect.";
 */

string cvs_version = "$Id: russian.pike,v 1.3 1999/02/28 19:20:23 grubba Exp $";

#define error(x) throw( ({ x, backtrace() }) )

string month(int num)
{
  return ({ "-A������", "�������", "����", "������", "���",-L
	      "-A����", "����", "�������", "��������", "������",-L
	      "-A������", "�������" })[num - 1];-L
}

string day(int num)
{
  return ({ "-A�����������","�����������","�������","�����", "�������",-L
	      "-A�������", "�������" }) [ num - 1 ];-L
}

string ordered(int i)
{
  return (string) i + "--A�";-L
}

string date(int timestamp, mapping m)
{
  mapping t1=localtime(timestamp);
  mapping t2=localtime(time(0));

  if(!m) m=([]);

  if(!(m["full"] || m["date"] || m["time"]))
  {
    if(t1["yday"] == t2["yday"] && t1["year"] == t2["year"])
      return "-A�������, � " + ctime(timestamp)[11..15];-L
  
    if(t1["yday"] == t2["yday"]-1 && t1["year"] == t2["year"])
      return "-A�����, v " + ctime(timestamp)[11..15];-L
  
    if(t1["yday"] == t2["yday"]+1 && t1["year"] == t2["year"])
      return "-A������, okolo "  + ctime(timestamp)[11..15];-L
  
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
   case 1:  return ([ "m" : "-A����",-L
		      "f" : "-A����",-L
		      "n" : "-A����" ])[gender];-L
   case 2:  return ("f" == gender) ? "-A��e" : "���";-L
   case 3:  return "-A���";-L
   case 4:  return "-A������";-L
   case 5:  return "-A����";-L
   case 6:  return "-A�����";-L
   case 7:  return "-A����";-L
   case 8:  return "-A������";-L
   case 9:  return "-A������";-L
   default:
     error("russian->_number_1: internal error.\n");
  }
}

string _number_10(int num)
{
  switch(num)
  {
   case 2: return "-A��������";-L
   case 3: return "-A��������";-L
   case 4: return "-A�����";-L
   case 5: return "-A���������";-L
   case 6: return "-A����������";-L
   case 7: return "-A���������";-L
   case 8: return "-A�����������";-L
   case 9: return "-A���������";-L
   default:
     error("russian->_number_10: internal error.\n");
  }
}

string _number_100(int num)
{
  switch(num)
  {
   case 1: return "-A���";-L
   case 2: return "-A������";-L
   case 3: case 4:
     return _number_1(num, "m")+"-A���";-L
   case 5: case 6: case 7: case 8: case 9:
     return _number_1(num, "m")+"-A���";-L
   default:
     error("russian->_number_10: internal error.\n");
  }
}

string _number(int num, string gender);

string _number_1000(int num)
{
  if (num == 1)
    return "-A������";-L

  string pre = _number(num, "f");
  switch(num % 10)
  {
   case 1: return pre + " -A������";-L
   case 2: case 3: case 4:
     return pre + " -A������";-L
   default:
     return pre + " -A�����";-L
  }
}

string _number_1000000(int num)
{
  if (num == 1)
    return "-A�������";-L

  string pre = _number(num, "m");
  switch(num % 10)
  {
   case 1: return pre + " -A�������";-L
   case 2: case 3: case 4:
     return pre + " -A��������";-L
   default:
     return pre + " -A���������";-L
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
    return ([ 10: "-A������",-L
	      11: "-A�����������",-L
	      12: "-A����������",-L
	      13: "-A����������",-L
	      14: "-A������������",-L
	      15: "-A����������",-L
	      16: "-A�����������",-L
	      17: "-A����������",-L
	      18: "-A������������",-L
	      19: "-A������������" ])[num];-L
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
    return("-A�����"+_number(-num, gender));-L
  } if (num) {
    return(_number(num, gender));
  } else {
    return("-A����");-L
  }
}

array aliases()
{
  return ({ "ru", "rus", "russian", "-A�������" });-L
}

